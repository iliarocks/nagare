import CoreData
import Observation
import OSLog
import SwiftData

@MainActor
protocol SyncHistoryObserving: AnyObject {
    var eventCounter: Int { get }
}

extension HistoryObserver: SyncHistoryObserving {}

typealias SyncHistoryObserverFactory = @MainActor (
    ModelContainer
) throws -> any SyncHistoryObserving

/// Publishes persisted changes immediately, then restores semantic invariants
/// on a separate debounce. Observation and partial-import failures retry for as
/// long as the runtime remains alive rather than degrading until relaunch.
@MainActor
final class SyncIntegrityMonitor {
    private static let logger = Logger(
        subsystem: Bundle.main.bundleIdentifier ?? "Nagare",
        category: "SyncIntegrity"
    )

    private let modelContainer: ModelContainer
    private let requiresReconciliation: Bool
    private let onPersistedChange: () throws -> Void
    private let makeHistoryObserver: SyncHistoryObserverFactory
    private var historyObserver: (any SyncHistoryObserving)?
    private var observationToken: ObservationTracking.Token?
    private var cloudObservationToken: NotificationCenter.ObservationToken?
    private var scheduledPublication: Task<Void, Never>?
    private var scheduledRepair: Task<Void, Never>?
    private var historyRetryTask: Task<Void, Never>?
    private var historyRetryIndex = 0
    private var pendingRetryIndex = 0
    private var repairFailureRetryIndex = 0
    private var hasHandledInitialActivation = false
    private var publicationFailed = false

    private static let retryDelays: [Duration] = [
        .seconds(1),
        .seconds(3),
        .seconds(8),
        .seconds(30),
        .seconds(120)
    ]
    private static let pendingRetryDelays: [Duration] = [.milliseconds(350)] + retryDelays

    init(
        modelContainer: ModelContainer,
        requiresReconciliation: Bool = true,
        onPersistedChange: @escaping () throws -> Void = {},
        historyObserverFactory: @escaping SyncHistoryObserverFactory = {
            try HistoryObserver(
                observedModels: NagareSchema.models,
                modelContainer: $0
            )
        }
    ) {
        self.modelContainer = modelContainer
        self.requiresReconciliation = requiresReconciliation
        self.onPersistedChange = onPersistedChange
        self.makeHistoryObserver = historyObserverFactory
        if requiresReconciliation {
            cloudObservationToken = NotificationCenter.default.addObserver(
                of: NSPersistentCloudKitContainer.self,
                for: .eventChanged
            ) { [weak self] message in
                Task { @MainActor [weak self] in
                    let event = message.event
                    guard event.endDate != nil else { return }
                    if event.succeeded {
                        if event.type == .import { self?.cloudImportDidFinish() }
                    } else {
                        Self.logger.error(
                            "CloudKit \(String(describing: event.type), privacy: .public) failed: \(event.error?.localizedDescription ?? "Unknown error", privacy: .public)"
                        )
                    }
                }
            }
        }
        ensureHistoryObservation()
    }

    deinit {
        if let cloudObservationToken {
            NotificationCenter.default.removeObserver(cloudObservationToken)
        }
        scheduledPublication?.cancel()
        scheduledRepair?.cancel()
        historyRetryTask?.cancel()
    }

    /// Coalesces the duplicate task/scene callbacks SwiftUI can deliver during
    /// launch. Later activations retry observation and perform one integrity
    /// pass in case a push or partial import was missed while suspended.
    func applicationDidBecomeActive() {
        historyRetryTask?.cancel()
        historyRetryTask = nil
        historyRetryIndex = 0
        ensureHistoryObservation()
        if publicationFailed { schedulePublication() }

        guard hasHandledInitialActivation else {
            hasHandledInitialActivation = true
            return
        }
        pendingRetryIndex = 0
        repairFailureRetryIndex = 0
        if requiresReconciliation {
            scheduleRepair(after: .milliseconds(100))
        }
    }

    func cloudImportDidFinish() {
        guard requiresReconciliation else { return }
        schedulePublication()
        pendingRetryIndex = 0
        repairFailureRetryIndex = 0
        scheduleRepair(after: .milliseconds(250))
    }

    func stop() {
        if let cloudObservationToken {
            NotificationCenter.default.removeObserver(cloudObservationToken)
        }
        cloudObservationToken = nil
        scheduledPublication?.cancel()
        scheduledPublication = nil
        scheduledRepair?.cancel()
        scheduledRepair = nil
        historyRetryTask?.cancel()
        historyRetryTask = nil
        observationToken = nil
        historyObserver = nil
    }

    func repair() {
        guard requiresReconciliation else { return }
        let context = ModelContext(modelContainer)
        context.autosaveEnabled = false
        context.author = NagareCloud.reconciliationHistoryAuthor
        do {
            let plan = try SyncReconciliationOrchestrator.reconcile(
                using: SwiftDataSyncReconciliationAdapter(context: context)
            )
            repairFailureRetryIndex = 0
            if plan.report.madeChanges {
                schedulePublication()
                Self.logger.notice(
                    "Reconciled imported sync state: projects=\(plan.report.duplicateProjectsRemoved), todos=\(plan.report.duplicateTodosRemoved), templates=\(plan.report.duplicateTemplatesRemoved), recurrence=\(plan.report.recurrenceConflictsRepaired), links=\(plan.report.recurrenceLinksRepaired), recordIDs=\(plan.report.syncRecordIDsAssigned)"
                )
            }
            if !plan.pendingTemplates.isEmpty {
                Self.logger.debug(
                    "Waiting for \(plan.pendingTemplates.count) partial recurrence import(s)."
                )
                retryPendingImports(plan.pendingTemplates)
            } else {
                pendingRetryIndex = 0
            }
        } catch {
            Self.logger.error(
                "Unable to reconcile imported sync state: \(error.localizedDescription, privacy: .public)"
            )
            retryRepairFailure()
        }
    }

    private func ensureHistoryObservation() {
        guard historyObserver == nil else { return }
        do {
            let observer = try makeHistoryObserver(modelContainer)
            historyObserver = observer
            historyRetryIndex = 0
            observationToken = withContinuousObservation(
                options: [.didSet]
            ) { [weak self, weak observer] _ in
                guard let self, let observer else { return }
                _ = observer.eventCounter
                self.handleHistoryEvent()
            }
        } catch {
            Self.logger.error(
                "Unable to monitor persistent history: \(error.localizedDescription, privacy: .public)"
            )
            scheduleHistoryRetry()
        }
    }

    private func handleHistoryEvent() {
        pendingRetryIndex = 0
        repairFailureRetryIndex = 0

        // Immutable snapshots tolerate transient duplicates and incomplete
        // relationships, so visible updates do not wait for a full graph scan.
        schedulePublication()
    }

    private func schedulePublication() {
        guard scheduledPublication == nil else { return }
        // Run outside the observation closure so reloading the published
        // snapshot doesn't subscribe this monitor to that snapshot itself.
        scheduledPublication = Task { [weak self] in
            guard !Task.isCancelled, let self else { return }
            self.scheduledPublication = nil
            do {
                try self.onPersistedChange()
                self.publicationFailed = false
            } catch {
                self.publicationFailed = true
                Self.logger.error(
                    "Unable to publish persisted data: \(error.localizedDescription, privacy: .public)"
                )
            }
        }
    }

    private func scheduleHistoryRetry() {
        historyRetryTask?.cancel()
        let delay = retryDelay(
            at: historyRetryIndex,
            in: Self.retryDelays
        )
        historyRetryIndex += 1
        historyRetryTask = Task { [weak self] in
            do {
                try await Task.sleep(for: delay)
            } catch {
                return
            }
            guard !Task.isCancelled, let self else { return }
            self.historyRetryTask = nil
            self.ensureHistoryObservation()
        }
    }

    private func retryPendingImports(_ pending: [SyncPendingTemplate]) {
        if pendingRetryIndex == Self.pendingRetryDelays.count {
            let diagnostics = pending.map {
                "\($0.templateID.uuidString):\(String(describing: $0.reason))"
            }.joined(separator: ",")
            Self.logger.error(
                "Recurrence imports entered long-tail retry: \(diagnostics, privacy: .public)"
            )
        }
        let delay = retryDelay(
            at: pendingRetryIndex,
            in: Self.pendingRetryDelays
        )
        pendingRetryIndex += 1
        scheduleRepair(after: delay)
    }

    private func retryRepairFailure() {
        let delay = retryDelay(
            at: repairFailureRetryIndex,
            in: Self.retryDelays
        )
        repairFailureRetryIndex += 1
        scheduleRepair(after: delay)
    }

    private func retryDelay(
        at index: Int,
        in delays: [Duration]
    ) -> Duration {
        delays[min(index, delays.count - 1)]
    }

    private func scheduleRepair(after delay: Duration) {
        scheduledRepair?.cancel()
        scheduledRepair = Task { [weak self] in
            do {
                try await Task.sleep(for: delay)
            } catch {
                return
            }
            guard !Task.isCancelled else { return }
            self?.repair()
        }
    }
}
