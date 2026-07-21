import Foundation
import SwiftData

enum TodoMaintenance {
    @MainActor
    static func rollUnfinishedTodosForward(
        in context: ModelContext,
        calendar: Calendar = .autoupdatingCurrent
    ) throws {
        let today = calendar.startOfDay(for: .now)
        var descriptor = FetchDescriptor<Todo>(
            predicate: #Predicate { todo in
                todo.completedAt == nil && todo.scheduledDate < today
            }
        )
        descriptor.sortBy = [
            SortDescriptor(\Todo.scheduledDate),
            SortDescriptor(\Todo.sortOrder),
            SortDescriptor(\Todo.createdAt)
        ]

        do {
            let overdueTodos = try context.fetch(descriptor)
            var nextOrder = try ItemOrdering.nextSortOrder(
                on: today,
                in: context,
                calendar: calendar
            )

            for todo in overdueTodos {
                todo.scheduledDate = today
                todo.sortOrder = nextOrder
                nextOrder += ItemOrdering.spacing
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
