import Foundation

nonisolated enum ItemID: Hashable, Sendable {
    case todo(UUID)
    case event(UUID)
}

enum Item: Identifiable {
    case todo(Todo)
    case event(Event)

    var id: ItemID {
        switch self {
        case .todo(let todo):
            ItemID.todo(todo.id)
        case .event(let event):
            ItemID.event(event.id)
        }
    }

    var order: String {
        switch self {
        case .todo(let todo):
            todo.order
        case .event(let event):
            event.order
        }
    }

    var scheduledDate: Date {
        switch self {
        case .todo(let todo):
            todo.scheduledDate
        case .event(let event):
            event.scheduledDate
        }
    }

    var isCompleted: Bool {
        switch self {
        case .todo(let todo):
            todo.completedAt != nil
        case .event:
            false
        }
    }

    func applyOrder(_ order: String) {
        switch self {
        case .todo(let todo):
            todo.order = order
        case .event(let event):
            event.order = order
        }
    }

    func move(to day: Date, calendar: Calendar = .autoupdatingCurrent) {
        let destinationDay = calendar.startOfDay(for: day)

        switch self {
        case .todo(let todo):
            todo.scheduledDate = destinationDay

        case .event(let event):
            let duration = event.endDate.map { $0.timeIntervalSince(event.scheduledDate) }
            let time = calendar.dateComponents(
                [.hour, .minute, .second],
                from: event.scheduledDate
            )
            let newStart = calendar.date(
                bySettingHour: time.hour ?? 0,
                minute: time.minute ?? 0,
                second: time.second ?? 0,
                of: destinationDay
            ) ?? destinationDay

            event.scheduledDate = newStart
            event.endDate = duration.map { newStart.addingTimeInterval($0) }
        }
    }

    @MainActor
    static func ordered(todos: [Todo], events: [Event]) -> [Item] {
        ordered(todos.map(Item.todo) + events.map(Item.event))
    }

    @MainActor
    static func ordered(_ items: [Item]) -> [Item] {
        items.sorted(by: areInIncreasingOrder)
    }

    private static func areInIncreasingOrder(
        _ first: Item,
        _ second: Item
    ) -> Bool {
        if first.order != second.order {
            return first.order < second.order
        }
        return first.id.description < second.id.description
    }
}

private extension ItemID {
    var description: String {
        switch self {
        case .todo(let id):
            "todo-\(id)"
        case .event(let id):
            "event-\(id)"
        }
    }
}
