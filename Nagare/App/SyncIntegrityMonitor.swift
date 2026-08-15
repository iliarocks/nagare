import Observation
import OSLog
import SwiftData

/// Bridges SwiftData persistent-history notifications to Nagare's semantic
/// invariant repair. CloudKit imports records incrementally, so the repair is
/// deliberately debounced and safe to repeat.
@MainActor
final class SyncIntegrityMonitor {
    private static let logger = Logger(
        subsystem: Bundle.main.bundleIdentifier ?? "Nagare",
        category: "SyncIntegrity"
    )

    private let modelContainer: ModelContainer
    private let historyObserver: HistoryObserver
    private let onReconciled: () -> Void
    private var observationToken: ObservationTracking.Token?
    private var scheduledRepair: Task<Void, Never>?
    private var pendingRetryIndex = 0

    private static let pendingRetryDelays: [Duration] = [
        .milliseconds(350),
        .seconds(1),
        .seconds(3),
        .seconds(8)
    ]

    init(
        modelContainer: ModelContainer,
        onReconciled: @escaping () -> Void = {}
    ) throws {
        self.modelContainer = modelContainer
        historyObserver = try HistoryObserver(
            observedModels: NagareSchemaV2.models,
            modelContainer: modelContainer
        )
        self.onReconciled = onReconciled
        observationToken = withContinuousObservation(
            options: [.didSet]
        ) { [weak self] _ in
            guard let self else { return }
            _ = self.historyObserver.eventCounter
            self.pendingRetryIndex = 0
            self.scheduleRepair(after: .milliseconds(250))
        }
        repair()
    }

    func repair() {
        let context = ModelContext(modelContainer)
        context.autosaveEnabled = false
        context.author = NagareCloud.reconciliationHistoryAuthor
        // Publication must not depend on semantic repair succeeding. A title
        // edit is still valid imported state when an unrelated relationship
        // arrives partially and repair needs a later retry.
        defer { onReconciled() }
        do {
            let plan = try SyncReconciliationOrchestrator.reconcile(
                using: SwiftDataSyncReconciliationAdapter(context: context)
            )
            if plan.report.madeChanges {
                Self.logger.notice(
                    "Reconciled imported sync state: projects=\(plan.report.duplicateProjectsRemoved), todos=\(plan.report.duplicateTodosRemoved), events=\(plan.report.duplicateEventsRemoved), templates=\(plan.report.duplicateTemplatesRemoved), recurrence=\(plan.report.recurrenceConflictsRepaired), links=\(plan.report.recurrenceLinksRepaired), recordIDs=\(plan.report.syncRecordIDsAssigned)"
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
            // A later history event or foreground activation will retry. Never
            // make a transient repair failure fatal to opening the local store.
            Self.logger.error(
                "Unable to reconcile imported sync state: \(error.localizedDescription, privacy: .public)"
            )
        }
    }

    private func retryPendingImports(
        _ pending: [SyncPendingTemplate]
    ) {
        guard pendingRetryIndex < Self.pendingRetryDelays.count else {
            if pendingRetryIndex == Self.pendingRetryDelays.count {
                let diagnostics = pending.map {
                    "\($0.templateID.uuidString):\(String(describing: $0.reason))"
                }.joined(separator: ",")
                Self.logger.error(
                    "Recurrence imports remained partial after bounded retries: \(diagnostics, privacy: .public)"
                )
                pendingRetryIndex += 1
            }
            return
        }

        let delay = Self.pendingRetryDelays[pendingRetryIndex]
        pendingRetryIndex += 1
        scheduleRepair(after: delay)
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
