import Foundation

enum ScheduledItemID: Hashable, Sendable {
    case todo(UUID)
    case event(UUID)
}

enum ScheduledItem: Identifiable {
    case todo(Todo)
    case event(Event)

    var id: ScheduledItemID {
        switch self {
        case .todo(let todo):
            .todo(todo.id)
        case .event(let event):
            .event(event.id)
        }
    }

    var sortOrder: Int64 {
        get {
            switch self {
            case .todo(let todo):
                todo.sortOrder
            case .event(let event):
                event.sortOrder
            }
        }
        nonmutating set {
            switch self {
            case .todo(let todo):
                todo.sortOrder = newValue
            case .event(let event):
                event.sortOrder = newValue
            }
        }
    }

    var createdAt: Date {
        switch self {
        case .todo(let todo):
            todo.createdAt
        case .event(let event):
            event.createdAt
        }
    }

    @MainActor
    static func ordered(todos: [Todo], events: [Event]) -> [ScheduledItem] {
        (todos.map(ScheduledItem.todo) + events.map(ScheduledItem.event))
            .sorted(by: areInIncreasingOrder)
    }

    private static func areInIncreasingOrder(
        _ first: ScheduledItem,
        _ second: ScheduledItem
    ) -> Bool {
        if first.sortOrder != second.sortOrder {
            return first.sortOrder < second.sortOrder
        }
        if first.createdAt != second.createdAt {
            return first.createdAt < second.createdAt
        }
        return first.id.description < second.id.description
    }
}

private extension ScheduledItemID {
    var description: String {
        switch self {
        case .todo(let id):
            "todo-\(id)"
        case .event(let id):
            "event-\(id)"
        }
    }
}
