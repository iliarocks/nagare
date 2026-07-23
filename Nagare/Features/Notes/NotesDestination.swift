enum NotesDestination: Identifiable, Hashable {
    case todo(Todo)
    case event(Event)
    case template(RecurrenceTemplate)

    var id: String {
        switch self {
        case .todo(let todo):
            "todo-\(todo.id)"
        case .event(let event):
            "event-\(event.id)"
        case .template(let template):
            "template-\(template.id)"
        }
    }

    init(_ item: Item) {
        switch item {
        case .todo(let todo):
            self = .todo(todo)
        case .event(let event):
            self = .event(event)
        }
    }

    static func == (lhs: NotesDestination, rhs: NotesDestination) -> Bool {
        switch (lhs, rhs) {
        case (.todo(let lhsTodo), .todo(let rhsTodo)):
            lhsTodo.id == rhsTodo.id
        case (.event(let lhsEvent), .event(let rhsEvent)):
            lhsEvent.id == rhsEvent.id
        case (.template(let lhsTemplate), .template(let rhsTemplate)):
            lhsTemplate.id == rhsTemplate.id
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
        case .template(let template):
            hasher.combine("template")
            hasher.combine(template.id)
        }
    }
}
