import AppIntents
import Foundation
import UniformTypeIdentifiers

@AppIntent(schema: .reminders.createReminder)
struct CreateNagareTodoIntent {
    var title: String
    var list: NagareReminderListEntity?
    var note: AttributedString?
    var isFlagged: Bool?
    var images: [IntentFile]
    var tags: Set<String>
    var urls: [URL]
    var dueDate: DateComponents?
    var recurrence: Calendar.RecurrenceRule?
    var locationTrigger: NagareLocationTriggerEntity?
    var section: NagareReminderSectionEntity?

    @Dependency var store: NagareIntentStore

    @MainActor
    func perform() async throws -> some ReturnsValue<NagareTodoEntity> & ProvidesDialog {
        if let list, list.id != NagareReminderListEntity.nagare.id {
            throw NagareIntentError.invalidNagareContainer
        }
        guard isFlagged != true,
              images.isEmpty,
              tags.isEmpty,
              urls.isEmpty,
              locationTrigger == nil,
              section == nil else {
            throw NagareIntentError.unsupportedReminderFeatures
        }
        guard recurrence == nil else {
            throw NagareIntentError.repeatCreationUnsupported
        }

        let title = try NagareIntentSemantics.title(from: title)
        let scheduledDate = try NagareIntentSemantics.todoDate(from: dueDate)
        let snapshot = try store.createTodo(
            title: title,
            notes: NagareIntentSemantics.notes(from: note),
            scheduledDate: scheduledDate
        )
        let entity = NagareTodoEntity(snapshot: snapshot)

        return .result(
            value: entity,
            dialog: "Added \(title) to Nagare for \(scheduledDate.formatted(date: .abbreviated, time: .omitted))."
        )
    }
}

@AppIntent(schema: .calendar.createEvent)
struct CreateNagareEventIntent {
    var title: String
    var startDate: Date
    var endDate: Date?
    var location: NagareEventLocation?
    var calendar: NagareCalendarEntity
    var isAllDay: Bool
    var recurrence: Calendar.RecurrenceRule?
    var attendees: [NagareAttendeeEntity]
    var note: AttributedString?

    @Dependency var store: NagareIntentStore

    @MainActor
    func perform() async throws -> some ReturnsValue<NagareEventEntity> & ProvidesDialog {
        guard calendar.id == NagareCalendarEntity.nagare.id else {
            throw NagareIntentError.invalidNagareContainer
        }
        guard !isAllDay else {
            throw NagareIntentError.allDayEventUnsupported
        }
        guard location == nil, attendees.isEmpty else {
            throw NagareIntentError.unsupportedEventFeatures
        }
        guard recurrence == nil else {
            throw NagareIntentError.repeatCreationUnsupported
        }
        try NagareIntentSemantics.validateEventRange(
            startDate: startDate,
            endDate: endDate
        )

        let title = try NagareIntentSemantics.title(from: title)
        let snapshot = try store.createEvent(
            title: title,
            notes: NagareIntentSemantics.notes(from: note),
            scheduledDate: startDate,
            endDate: endDate
        )
        let entity = NagareEventEntity(snapshot: snapshot)

        return .result(
            value: entity,
            dialog: "Added \(title) to Nagare for \(startDate.formatted(date: .abbreviated, time: .shortened))."
        )
    }
}
