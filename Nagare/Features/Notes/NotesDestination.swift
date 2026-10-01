import Foundation

enum NotesDestination: Identifiable, Hashable {
    case todo(UUID)
    case template(UUID)
    case virtualOccurrence(templateID: UUID, schedule: NotesSchedule)

    var id: Self { self }

    var recordID: NoteRecordID {
        switch self {
        case .todo(let id): .todo(id)
        case .template(let id): .recurrenceTemplate(id)
        case .virtualOccurrence(let id, _): .recurrenceTemplate(id)
        }
    }

    init(_ item: ItemRecordSnapshot) {
        self = .todo(item.id)
    }

    init(_ item: VirtualItem) {
        self = .virtualOccurrence(
            templateID: item.template.id,
            schedule: NotesSchedule(
                scheduledDate: item.startDate ?? item.date,
                includesTime: item.startDate != nil,
                endDate: item.endDate
            )
        )
    }

    func schedule(in snapshot: NagareDataSnapshot) -> NotesSchedule? {
        if case .virtualOccurrence(_, let schedule) = self {
            return schedule
        }
        return editableScheduledItem(in: snapshot).map { NotesSchedule($0) }
    }

    func editableScheduledItem(
        in snapshot: NagareDataSnapshot
    ) -> ItemRecordSnapshot? {
        switch self {
        case .todo(let id):
            snapshot.todosByID[id]
        case .template(let id):
            snapshot.templatesByID[id].flatMap { snapshot.currentItem(for: $0) }
        case .virtualOccurrence:
            nil
        }
    }

    func recurrenceTemplate(
        in snapshot: NagareDataSnapshot
    ) -> RecurrenceTemplateRecordSnapshot? {
        switch self {
        case .todo(let id):
            snapshot.todosByID[id]?.recurrenceTemplateID.flatMap {
                snapshot.templatesByID[$0]
            }
        case .template(let id), .virtualOccurrence(let id, _):
            snapshot.templatesByID[id]
        }
    }
}

struct NotesSchedule: Hashable {
    let scheduledDate: Date
    let includesTime: Bool
    let endDate: Date?

    init(scheduledDate: Date, includesTime: Bool, endDate: Date?) {
        self.scheduledDate = scheduledDate
        self.includesTime = includesTime
        self.endDate = endDate
    }

    init(_ item: ItemRecordSnapshot) {
        self.init(
            scheduledDate: item.scheduledDate,
            includesTime: item.includesTime,
            endDate: item.endDate
        )
    }
}
