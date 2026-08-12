import Foundation

/// Side-effect boundary for semantic reconciliation. Implementations may load
/// and apply data, but all conflict policy lives in the pure planner.
@MainActor
protocol SyncReconciliationPersistence: AnyObject {
    func loadSyncGraph() throws -> SyncGraphSnapshot
    func apply(_ mutations: [SyncReconciliationMutation]) throws
    func save(at transactionDate: Date) throws
    func rollback()
}

nonisolated enum SyncReconciliationPersistenceError: Error, LocalizedError {
    case loadFailed(String)
    case applyFailed(String)
    case saveFailed(String)

    var errorDescription: String? {
        switch self {
        case .loadFailed(let message):
            "Nagare couldn't read its synchronized data. \(message)"
        case .applyFailed(let message):
            "Nagare couldn't reconcile its synchronized data. \(message)"
        case .saveFailed(let message):
            "Nagare couldn't save reconciled data. \(message)"
        }
    }
}
