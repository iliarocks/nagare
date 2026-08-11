import Foundation

enum NagareIntentError: Error, LocalizedError, Equatable {
    case emptyTitle
    case todoCannotHaveTime
    case allDayEventUnsupported
    case eventEndBeforeStart
    case pastTodoDate
    case dateCouldNotBeResolved
    case unsupportedReminderFeatures
    case unsupportedEventFeatures
    case invalidNagareContainer
    case repeatCreationUnsupported

    var errorDescription: String? {
        switch self {
        case .emptyTitle:
            "Nagare needs a title before it can create the item. (SIRI-001)"
        case .todoCannotHaveTime:
            "Nagare Todos are intentionally untimed. Create an Event instead when something has a specific time. (SIRI-002)"
        case .allDayEventUnsupported:
            "Nagare doesn't use all-day Events. Create an untimed Todo instead. (SIRI-004)"
        case .eventEndBeforeStart:
            "The Event's end time must be later than its start time. (SIRI-005)"
        case .pastTodoDate:
            "Nagare Todos must be scheduled for today or a future day. (SIRI-006)"
        case .dateCouldNotBeResolved:
            "Nagare couldn't understand that date. Try including the full day, month, and year. (SIRI-007)"
        case .unsupportedReminderFeatures:
            "Nagare Todos don't currently support flags, attachments, tags, links, sections, or location triggers. (SIRI-013)"
        case .unsupportedEventFeatures:
            "Nagare Events don't currently support locations or attendees. (SIRI-014)"
        case .invalidNagareContainer:
            "Nagare only has one Todo list and one Event calendar. (SIRI-015)"
        case .repeatCreationUnsupported:
            "Nagare doesn't currently support creating repeating items through Siri. Create the repeating item in Nagare instead. (SIRI-019)"
        }
    }
}

enum NagareIntentSemantics {
    static func title(from value: String) throws -> String {
        let title = value.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !title.isEmpty else {
            throw NagareIntentError.emptyTitle
        }
        return title
    }

    static func notes(from value: AttributedString?) -> String? {
        guard let value else {
            return nil
        }
        let notes = String(value.characters)
        return notes.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            ? nil
            : notes
    }

    static func todoDate(
        from components: DateComponents?,
        now: Date = .now,
        calendar: Calendar = .autoupdatingCurrent
    ) throws -> Date {
        guard let components else {
            return calendar.startOfDay(for: now)
        }

        if components.hour != nil
            || components.minute != nil
            || components.second != nil
            || components.nanosecond != nil {
            throw NagareIntentError.todoCannotHaveTime
        }

        var resolvingCalendar = components.calendar ?? calendar
        if let timeZone = components.timeZone {
            resolvingCalendar.timeZone = timeZone
        }
        guard let date = resolvingCalendar.date(from: components) else {
            throw NagareIntentError.dateCouldNotBeResolved
        }

        let day = resolvingCalendar.startOfDay(for: date)
        guard day >= resolvingCalendar.startOfDay(for: now) else {
            throw NagareIntentError.pastTodoDate
        }
        return day
    }

    static func validateEventRange(
        startDate: Date,
        endDate: Date?
    ) throws {
        if let endDate, endDate <= startDate {
            throw NagareIntentError.eventEndBeforeStart
        }
    }
}
