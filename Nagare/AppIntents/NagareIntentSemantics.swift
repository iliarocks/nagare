import Foundation

enum NagareIntentError: Error, LocalizedError, Equatable {
    case emptyTitle
    case todoCannotHaveTime
    case eventRequiresTime
    case allDayEventUnsupported
    case eventEndBeforeStart
    case pastTodoDate
    case dateCouldNotBeResolved
    case unsupportedReminderFeatures
    case unsupportedEventFeatures
    case invalidNagareContainer
    case itemNotFound
    case itemNotOnToday
    case ambiguousTodayItem
    case repeatCreationUnsupported
    case unsupportedReminderUpdate
    case unsupportedEventSpan

    var errorDescription: String? {
        switch self {
        case .emptyTitle:
            "Nagare needs a title before it can create the item. (SIRI-001)"
        case .todoCannotHaveTime:
            "Nagare Todos are intentionally untimed. Create an Event instead when something has a specific time. (SIRI-002)"
        case .eventRequiresTime:
            "Nagare Events need a specific start time. Create a Todo instead when it can happen anytime that day. (SIRI-003)"
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
        case .itemNotFound:
            "Nagare couldn't find that item. (SIRI-016)"
        case .itemNotOnToday:
            "Nagare couldn't find that item on Today. ‘What comes after’ only uses the current Today list. (SIRI-017)"
        case .ambiguousTodayItem:
            "More than one item on Today has that title. Rename one of them so Nagare can tell which item you mean. (SIRI-018)"
        case .repeatCreationUnsupported:
            "Nagare doesn't currently support creating repeating items through Siri. Create the repeating item in Nagare instead. (SIRI-019)"
        case .unsupportedReminderUpdate:
            "That Todo change isn't supported through Siri yet. Nagare currently supports completing or reinstating a Todo. (SIRI-020)"
        case .unsupportedEventSpan:
            "Nagare couldn't apply that deletion scope to this Event. (SIRI-021)"
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

}

enum NagareRecurrenceBridge {
    static func systemRule(
        from rule: RecurrenceRule?,
        calendar: Calendar = .autoupdatingCurrent
    ) -> Calendar.RecurrenceRule? {
        guard let rule, rule.mode == .absolute else {
            return nil
        }

        switch rule.unit {
        case .day:
            return .daily(calendar: calendar, interval: rule.interval)
        case .week:
            return .weekly(
                calendar: calendar,
                interval: rule.interval,
                weekdays: rule.anchors.map {
                    .every(weekday(for: $0))
                }
            )
        case .month:
            return .monthly(
                calendar: calendar,
                interval: rule.interval,
                daysOfTheMonth: rule.anchors.map { $0 + 1 }
            )
        case .year:
            return .yearly(calendar: calendar, interval: rule.interval)
        }
    }

    private static func weekday(for anchor: Int) -> Locale.Weekday {
        switch anchor {
        case 0: .monday
        case 1: .tuesday
        case 2: .wednesday
        case 3: .thursday
        case 4: .friday
        case 5: .saturday
        default: .sunday
        }
    }
}
