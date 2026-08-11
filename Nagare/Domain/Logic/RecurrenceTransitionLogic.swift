import Foundation

nonisolated enum RecurrenceTransitionLogic {
    enum TransitionError: Error, Equatable, Sendable {
        case missingEventStartTime
        case eventTimeCalculationFailed
        case sequenceOverflow
        case eventCrossesDateBoundary
        case eventEndsBeforeItStarts
    }

    static func nextTodo(
        after current: RecurrenceOccurrenceSnapshot,
        from template: RecurrenceTransitionTemplate,
        createdAt: Date,
        calendar: Calendar
    ) throws -> TodoOccurrenceDraft {
        TodoOccurrenceDraft(
            title: template.title,
            notes: template.notes,
            scheduledDate: try RecurrenceCalculator.nextDate(
                after: current.scheduledDate,
                using: template.rule,
                calendar: calendar
            ),
            createdAt: createdAt,
            order: current.order,
            projectOrder: current.projectOrder,
            sequence: try incrementedSequence(template.currentSequence)
        )
    }

    static func nextEvent(
        after current: RecurrenceOccurrenceSnapshot,
        from template: RecurrenceTransitionTemplate,
        createdAt: Date,
        calendar: Calendar
    ) throws -> EventOccurrenceDraft {
        let nextDay = try RecurrenceCalculator.nextDate(
            after: current.scheduledDate,
            using: template.rule,
            calendar: calendar
        )
        guard let startTimeSeconds = template.startTimeSeconds else {
            throw TransitionError.missingEventStartTime
        }
        return EventOccurrenceDraft(
            title: template.title,
            notes: template.notes,
            scheduledDate: try date(
                on: nextDay,
                wallTimeSeconds: startTimeSeconds,
                calendar: calendar
            ),
            endDate: try template.endTimeSeconds.map {
                try date(
                    on: nextDay,
                    wallTimeSeconds: $0,
                    calendar: calendar
                )
            },
            createdAt: createdAt,
            order: current.order,
            projectOrder: current.projectOrder,
            sequence: try incrementedSequence(template.currentSequence)
        )
    }

    static func eventWallTimes(
        scheduledDate: Date,
        endDate: Date?,
        calendar: Calendar
    ) throws -> (start: Int, end: Int?) {
        let start = wallTimeSeconds(for: scheduledDate, calendar: calendar)
        guard let endDate else {
            return (start, nil)
        }
        guard calendar.isDate(endDate, inSameDayAs: scheduledDate) else {
            throw TransitionError.eventCrossesDateBoundary
        }
        let end = wallTimeSeconds(for: endDate, calendar: calendar)
        guard end >= start else {
            throw TransitionError.eventEndsBeforeItStarts
        }
        return (start, end)
    }

    private static func wallTimeSeconds(
        for date: Date,
        calendar: Calendar
    ) -> Int {
        let components = calendar.dateComponents(
            [.hour, .minute, .second],
            from: date
        )
        return (components.hour ?? 0) * 3_600
            + (components.minute ?? 0) * 60
            + (components.second ?? 0)
    }

    private static func date(
        on day: Date,
        wallTimeSeconds: Int,
        calendar: Calendar
    ) throws -> Date {
        let hour = wallTimeSeconds / 3_600
        let minute = wallTimeSeconds % 3_600 / 60
        let second = wallTimeSeconds % 60
        guard let date = calendar.date(
            bySettingHour: hour,
            minute: minute,
            second: second,
            of: calendar.startOfDay(for: day)
        ) else {
            throw TransitionError.eventTimeCalculationFailed
        }
        return date
    }

    private static func incrementedSequence(_ sequence: Int) throws -> Int {
        let (next, overflow) = sequence.addingReportingOverflow(1)
        guard !overflow else {
            throw TransitionError.sequenceOverflow
        }
        return next
    }
}
