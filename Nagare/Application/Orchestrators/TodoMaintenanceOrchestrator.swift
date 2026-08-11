import Foundation

@MainActor
enum TodoMaintenanceOrchestrator {
    static func rollUnfinishedTodosForward(
        using persistence: any ItemOrderingPersistence,
        calendar: Calendar,
        now: Date
    ) throws {
        do {
            let items = try persistence.loadItems()
            let plan = try TodoMaintenanceLogic.rollForward(
                items,
                to: now,
                calendar: calendar
            )
            guard !plan.changes.isEmpty else {
                return
            }
            try persistence.apply(plan.changes)
            try persistence.save()
        } catch {
            persistence.rollback()
            if let error = error as? OrderingPlanner.PlanningError {
                throw error
            }
            if let error = error as? OrderingPersistenceError {
                throw error
            }
            throw OrderingPersistenceError.saveFailed(
                error.localizedDescription
            )
        }
    }
}
