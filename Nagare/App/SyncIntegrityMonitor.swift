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
    private let onPersistedChange: () -> Void
    private let onObservationHealthChanged: (Bool, String?) -> Void
    private let makeHistoryObserver: SyncHistoryObserverFactory
    private var historyObserver: (any SyncHistoryObserving)?
    private var observationToken: ObservationTracking.Token?
    private var scheduledRepair: Task<Void, Never>?
    private var historyRetryTask: Task<Void, Never>?
    private var historyRetryIndex = 0
    private var pendingRetryIndex = 0
    private var repairFailureRetryIndex = 0
    private var hasHandledInitialActivation = false

    private(set) var isObservingHistory = false

    private static let historyRetryDelays: [Duration] = [
        .seconds(1),
        .seconds(3),
        .seconds(8),
        .seconds(30),
        .seconds(120)
    ]
    private static let pendingRetryDelays: [Duration] = [
        .milliseconds(350),
        .seconds(1),
        .seconds(3),
        .seconds(8),
        .seconds(30),
        .seconds(120)
    ]
    private static let repairFailureRetryDelays: [Duration] = [
        .seconds(1),
        .seconds(3),
        .seconds(8),
        .seconds(30),
        .seconds(120)
    ]

    init(
        modelContainer: ModelContainer,
        requiresReconciliation: Bool = true,
        onPersistedChange: @escaping () -> Void = {},
        onObservationHealthChanged: @escaping (Bool, String?) -> Void = {
            _, _ in
        },
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
        self.onObservationHealthChanged = onObservationHealthChanged
        self.makeHistoryObserver = historyObserverFactory
        ensureHistoryObservation()
    }

    deinit {
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
        pendingRetryIndex = 0
        repairFailureRetryIndex = 0
        scheduleRepair(after: .milliseconds(250))
    }

    func stop() {
        scheduledRepair?.cancel()
        scheduledRepair = nil
        historyRetryTask?.cancel()
        historyRetryTask = nil
        observationToken = nil
        historyObserver = nil
        isObservingHistory = false
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
                onPersistedChange()
            }
            if plan.report.madeChanges {
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
            isObservingHistory = true
            onObservationHealthChanged(true, nil)
            historyRetryIndex = 0
            observationToken = withContinuousObservation(
                options: [.didSet]
            ) { [weak self, weak observer] _ in
                guard let self, let observer else { return }
                _ = observer.eventCounter
                self.handleHistoryEvent()
            }
        } catch {
            isObservingHistory = false
            onObservationHealthChanged(false, error.localizedDescription)
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
        onPersistedChange()
    }

    private func scheduleHistoryRetry() {
        historyRetryTask?.cancel()
        let delay = retryDelay(
            at: historyRetryIndex,
            in: Self.historyRetryDelays
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
            in: Self.repairFailureRetryDelays
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
