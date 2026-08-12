import Foundation

enum SwiftDataItem: Identifiable {
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

    var kind: ItemDraftKind {
        switch self {
        case .todo: .todo
        case .event: .event
        }
    }

    var createdAt: Date {
        switch self {
        case .todo(let todo): todo.createdAt
        case .event(let event): event.createdAt
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

    var project: Project? {
        switch self {
        case .todo(let todo):
            todo.project
        case .event(let event):
            event.project
        }
    }

    var projectOrder: String? {
        switch self {
        case .todo(let todo):
            todo.projectOrder
        case .event(let event):
            event.projectOrder
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

    var snapshot: ItemSnapshot {
        switch self {
        case .todo(let todo):
            ItemSnapshot(
                id: id,
                kind: .todo,
                scheduledDate: todo.scheduledDate,
                endDate: nil,
                completedAt: todo.completedAt,
                createdAt: todo.createdAt,
                order: todo.order,
                projectID: todo.project?.id,
                projectOrder: todo.projectOrder
            )
        case .event(let event):
            ItemSnapshot(
                id: id,
                kind: .event,
                scheduledDate: event.scheduledDate,
                endDate: event.endDate,
                completedAt: nil,
                createdAt: event.createdAt,
                order: event.order,
                projectID: event.project?.id,
                projectOrder: event.projectOrder
            )
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

    func applyProjectOrder(_ order: String?) {
        switch self {
        case .todo(let todo):
            todo.projectOrder = order
        case .event(let event):
            event.projectOrder = order
        }
    }

    func applyProject(_ project: Project?) {
        switch self {
        case .todo(let todo):
            todo.project = project
        case .event(let event):
            event.project = project
        }
    }

    func applySchedule(scheduledDate: Date, endDate: Date?) {
        switch self {
        case .todo(let todo):
            todo.scheduledDate = scheduledDate
        case .event(let event):
            event.scheduledDate = scheduledDate
            event.endDate = endDate
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
    static func ordered(todos: [Todo], events: [Event]) -> [SwiftDataItem] {
        ordered(todos.map(SwiftDataItem.todo) + events.map(SwiftDataItem.event))
    }

    @MainActor
    static func ordered(_ items: [SwiftDataItem]) -> [SwiftDataItem] {
        items.sorted(by: areInIncreasingOrder)
    }

    @MainActor
    static func orderedInProject(todos: [Todo], events: [Event]) -> [SwiftDataItem] {
        (todos.map(SwiftDataItem.todo) + events.map(SwiftDataItem.event)).sorted {
            switch ($0.projectOrder, $1.projectOrder) {
            case let (.some(first), .some(second)) where first != second:
                return first < second
            case (.some, .none):
                return true
            case (.none, .some):
                return false
            default:
                return $0.id.description < $1.id.description
            }
        }
    }

    private static func areInIncreasingOrder(
        _ first: SwiftDataItem,
        _ second: SwiftDataItem
    ) -> Bool {
        if first.order != second.order {
            return first.order < second.order
        }
        return first.id.description < second.id.description
    }
}
