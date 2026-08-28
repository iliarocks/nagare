import Foundation

enum NotesDestination: Identifiable, Hashable {
    case todo(UUID)
    case template(UUID)

    var id: String {
        switch self {
        case .todo(let id): "todo-\(id)"
        case .template(let id): "template-\(id)"
        }
    }

    var recordID: NoteRecordID {
        switch self {
        case .todo(let id): .todo(id)
        case .template(let id): .recurrenceTemplate(id)
        }
    }

    init(_ item: ItemRecordSnapshot) {
        self = .todo(item.id)
    }
}
