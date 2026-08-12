import Foundation

/// Laminates an immutable graph, deterministic policy, and one atomic I/O
/// adapter. Failure never crosses the boundary with pending mutations intact.
@MainActor
enum SyncReconciliationOrchestrator {
    static func reconcile(
        using persistence: any SyncReconciliationPersistence
    ) throws -> SyncReconciliationPlan {
        let snapshot: SyncGraphSnapshot
        do {
            snapshot = try persistence.loadSyncGraph()
        } catch {
            persistence.rollback()
            throw map(error, as: .load)
        }

        let plan = SyncReconciliationPlanner.plan(for: snapshot)
        guard plan.hasChanges else { return plan }

        do {
            try persistence.apply(plan.mutations)
        } catch {
            persistence.rollback()
            throw map(error, as: .apply)
        }

        do {
            try persistence.save(at: plan.transactionDate)
            return plan
        } catch {
            persistence.rollback()
            throw map(error, as: .save)
        }
    }

    private enum Operation {
        case load
        case apply
        case save
    }

    private static func map(
        _ error: Error,
        as operation: Operation
    ) -> Error {
        if error is SyncReconciliationPersistenceError {
            return error
        }
        switch operation {
        case .load:
            return SyncReconciliationPersistenceError.loadFailed(
                error.localizedDescription
            )
        case .apply:
            return SyncReconciliationPersistenceError.applyFailed(
                error.localizedDescription
            )
        case .save:
            return SyncReconciliationPersistenceError.saveFailed(
                error.localizedDescription
            )
        }
    }
}
