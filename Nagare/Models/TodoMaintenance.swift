import Foundation
import SwiftData

enum TodoMaintenance {
    @MainActor
    static func rollUnfinishedTodosForward(
        in context: ModelContext,
        calendar: Calendar = .autoupdatingCurrent
    ) throws {
        let today = calendar.startOfDay(for: .now)
        let descriptor = FetchDescriptor<Todo>(
            predicate: #Predicate { todo in
                todo.completedAt == nil && todo.scheduledDate < today
            }
        )

        do {
            for todo in try context.fetch(descriptor) {
                todo.scheduledDate = today
            }

            if context.hasChanges {
                try context.save()
            }
        } catch {
            context.rollback()
            throw error
        }
    }
}
