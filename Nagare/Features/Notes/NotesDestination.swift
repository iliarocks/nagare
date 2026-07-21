enum NotesDestination: Identifiable, Hashable {
    case todo(Todo)
    case event(Event)

    var id: String {
        switch self {
        case .todo(let todo):
            "todo-\(todo.id)"
        case .event(let event):
            "event-\(event.id)"
        }
    }

    static func == (lhs: NotesDestination, rhs: NotesDestination) -> Bool {
        switch (lhs, rhs) {
        case (.todo(let lhsTodo), .todo(let rhsTodo)):
            lhsTodo.id == rhsTodo.id
        case (.event(let lhsEvent), .event(let rhsEvent)):
            lhsEvent.id == rhsEvent.id
        default:
            false
        }
    }

    func hash(into hasher: inout Hasher) {
        switch self {
        case .todo(let todo):
            hasher.combine("todo")
            hasher.combine(todo.id)
        case .event(let event):
            hasher.combine("event")
            hasher.combine(event.id)
        }
    }
}
