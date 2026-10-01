import Foundation

/// A captured calendar day shared by maintenance and date-based lists.
nonisolated struct NagareCalendarDay: Equatable {
    let start: Date
    let calendar: Calendar

    init(now: Date, calendar: Calendar) {
        self.calendar = calendar
        start = calendar.startOfDay(for: now)
    }

    var nextStart: Date? {
        calendar.date(byAdding: .day, value: 1, to: start)
    }
}
