import AppIntents
import Foundation
import UniformTypeIdentifiers

@AppIntent(schema: .reminders.updateReminder)
struct UpdateNagareTodoIntent {
    var target: NagareTodoEntity
    var title: String?
    var note: AttributedString?
    var images: [IntentFile]?
    var subtasks: [NagareTodoEntity]?
    var tags: Set<String>?
    var urls: [URL]?
    var dueDate: DateComponents?
    var recurrence: Calendar.RecurrenceRule?
    var isCompleted: Bool?
    var isFlagged: Bool?
    var list: NagareReminderListEntity?
    var section: NagareReminderSectionEntity?
    var locationTrigger: NagareLocationTriggerEntity?

    @Dependency var store: NagareIntentStore

    @MainActor
    func perform() async throws -> some ReturnsValue<NagareTodoEntity> & ProvidesDialog {
        guard title == nil,
              note == nil,
              images == nil,
              subtasks == nil,
              tags == nil,
              urls == nil,
              dueDate == nil,
              recurrence == nil,
              isFlagged == nil,
              list == nil,
              section == nil,
              locationTrigger == nil,
              let isCompleted else {
            throw NagareIntentError.unsupportedReminderUpdate
        }

        let result = try store.setTodoCompletion(
            target.id,
            isCompleted: isCompleted
        )
        let entity = NagareTodoEntity(snapshot: result.item)
        try? await store.refreshSearchIndex()

        let dialog: String
        if isCompleted {
            if let next = result.nextOccurrence {
                dialog = "Completed \(result.item.title). Its repeat remains active, with the next occurrence on \(next.scheduledDate.formatted(date: .abbreviated, time: .omitted))."
            } else {
                dialog = "Completed \(result.item.title)."
            }
        } else {
            dialog = "Returned \(result.item.title) to Today."
        }

        return .result(value: entity, dialog: "\(dialog)")
    }
}

@AppIntent(schema: .reminders.deleteReminders)
struct DeleteNagareTodosIntent: DeleteIntent {
    var entities: [NagareTodoEntity]

    @Dependency var store: NagareIntentStore

    @MainActor
    func perform() async throws -> some IntentResult & ProvidesDialog {
        let results = try store.deleteTodos(
            identifiedBy: entities.map(\.id)
        )
        try? await store.refreshSearchIndex()

        let continuingRepeats = results.compactMap(\.nextOccurrence)
        let dialog: String
        if results.count == 1, let result = results.first {
            if let next = result.nextOccurrence {
                dialog = "Deleted \(result.title). Its repeat remains active, with the next occurrence on \(next.scheduledDate.formatted(date: .abbreviated, time: .omitted))."
            } else {
                dialog = "Deleted \(result.title)."
            }
        } else if continuingRepeats.isEmpty {
            dialog = "Deleted \(results.count) Todos."
        } else {
            dialog = "Deleted \(results.count) Todos. \(continuingRepeats.count) repeats remain active."
        }

        return .result(dialog: "\(dialog)")
    }
}

@AppEnum(schema: .calendar.eventSpan)
enum NagareEventSpan: String {
    case this
    case future
    case all

    static let caseDisplayRepresentations: [Self: DisplayRepresentation] = [
        .this: "This Event",
        .future: "This and Future Events",
        .all: "All Events"
    ]
}

@AppIntent(schema: .calendar.deleteEvent)
struct DeleteNagareEventIntent {
    var entity: NagareEventEntity
    var span: NagareEventSpan?

    @Dependency var store: NagareIntentStore

    @MainActor
    func perform() async throws -> some IntentResult & ProvidesDialog {
        let result = try store.deleteEvent(
            identifiedBy: entity.id,
            span: span
        )
        try? await store.refreshSearchIndex()

        let dialog: String
        if let next = result.nextOccurrence {
            dialog = "Deleted \(result.title). Its repeat remains active, with the next occurrence on \(next.scheduledDate.formatted(date: .abbreviated, time: .shortened))."
        } else {
            dialog = "Deleted \(result.title)."
        }
        return .result(dialog: "\(dialog)")
    }
}
