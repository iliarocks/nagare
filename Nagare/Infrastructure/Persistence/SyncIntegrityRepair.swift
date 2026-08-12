import SwiftData

typealias SyncIntegrityRepairReport = SyncReconciliationReport

/// Compatibility facade while callers migrate to the reconciliation
/// orchestrator. Policy is pure; this type only wires the SwiftData adapter.
@MainActor
enum SyncIntegrityRepair {
    static func repair(
        in context: ModelContext
    ) throws -> SyncIntegrityRepairReport {
        try SyncReconciliationOrchestrator.reconcile(
            using: SwiftDataSyncReconciliationAdapter(context: context)
        ).report
    }
}
