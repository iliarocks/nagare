import Foundation

enum NotesDestination: Identifiable, Hashable {
    case todo(UUID)
    case event(UUID)
    case template(UUID)

    var id: String {
        switch self {
        case .todo(let id): "todo-\(id)"
        case .event(let id): "event-\(id)"
        case .template(let id): "template-\(id)"
        }
    }

    var recordID: NoteRecordID {
        switch self {
        case .todo(let id): .todo(id)
        case .event(let id): .event(id)
        case .template(let id): .recurrenceTemplate(id)
        }
    }

    init(_ item: ItemRecordSnapshot) {
        switch item {
        case .todo(let todo): self = .todo(todo.id)
        case .event(let event): self = .event(event.id)
        }
    }
}
