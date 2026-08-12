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

    private let context: ModelContext
    private let historyObserver: HistoryObserver

    init(modelContainer: ModelContainer) throws {
        context = modelContainer.mainContext
        historyObserver = try HistoryObserver(
            observedModels: NagareSchemaV2.models,
            modelContainer: modelContainer
        )
    }

    var eventCounter: Int {
        historyObserver.eventCounter
    }

    func repair() {
        do {
            let report = try SyncIntegrityRepair.repair(in: context)
            guard report.madeChanges else { return }
            Self.logger.notice(
                "Reconciled imported sync state: projects=\(report.duplicateProjectsRemoved), todos=\(report.duplicateTodosRemoved), events=\(report.duplicateEventsRemoved), templates=\(report.duplicateTemplatesRemoved), recurrence=\(report.recurrenceConflictsRepaired), recordIDs=\(report.syncRecordIDsAssigned)"
            )
        } catch {
            // A later history event or foreground activation will retry. Never
            // make a transient repair failure fatal to opening the local store.
            context.rollback()
            Self.logger.error(
                "Unable to reconcile imported sync state: \(error.localizedDescription, privacy: .public)"
            )
        }
    }
}
