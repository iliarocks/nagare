import Foundation

nonisolated enum RecurrenceTransitionLogic {
    enum TransitionError: Error, Equatable, Sendable {
        case timeCalculationFailed
        case sequenceOverflow
        case crossesDateBoundary
        case invalidTime
    }

    static func nextTodo(
        after current: RecurrenceOccurrenceSnapshot,
        from template: RecurrenceTransitionTemplate,
        createdAt: Date,
        calendar: Calendar
    ) throws -> TodoOccurrenceDraft? {
        let nextDay = try RecurrenceCalculator.nextDate(
            after: current.scheduledDate,
            using: template.rule,
            calendar: calendar
        )
        guard template.rule.permits(nextDay, calendar: calendar) else {
            return nil
        }
        let startDate = try template.startTimeSeconds.map {
            try date(on: nextDay, wallTimeSeconds: $0, calendar: calendar)
        }
        let endDate = try template.endTimeSeconds.map {
            try date(on: nextDay, wallTimeSeconds: $0, calendar: calendar)
        }
        return TodoOccurrenceDraft(
            title: template.title,
            notes: template.notes,
            scheduledDate: startDate ?? calendar.startOfDay(for: nextDay),
            includesTime: startDate != nil,
            endDate: endDate,
            createdAt: createdAt,
            order: current.order,
            projectOrder: current.projectOrder,
            sequence: try incrementedSequence(template.currentSequence)
        )
    }

    static func wallTimes(
        scheduledDate: Date,
        endDate: Date?,
        calendar: Calendar
    ) throws -> (start: Int, end: Int?) {
        let start = wallTimeSeconds(for: scheduledDate, calendar: calendar)
        guard let endDate else { return (start, nil) }
        guard calendar.isDate(endDate, inSameDayAs: scheduledDate) else {
            throw TransitionError.crossesDateBoundary
        }
        let end = wallTimeSeconds(for: endDate, calendar: calendar)
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
        guard (0..<86_400).contains(wallTimeSeconds) else {
            throw TransitionError.invalidTime
        }
        let hour = wallTimeSeconds / 3_600
        let minute = wallTimeSeconds % 3_600 / 60
        let second = wallTimeSeconds % 60
        guard let date = calendar.date(
            bySettingHour: hour,
            minute: minute,
            second: second,
            of: calendar.startOfDay(for: day)
        ) else {
            throw TransitionError.timeCalculationFailed
        }
        return date
    }

    private static func incrementedSequence(_ sequence: Int) throws -> Int {
        let (next, overflow) = sequence.addingReportingOverflow(1)
        guard !overflow else { throw TransitionError.sequenceOverflow }
        return next
    }
}
