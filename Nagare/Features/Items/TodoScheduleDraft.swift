import Foundation

struct TodoScheduleDraft: Equatable {
    struct Schedule: Equatable {
        let date: Date
        let includesTime: Bool
        let endDate: Date?
    }

    var scheduledDate: Date
    var includesTime: Bool
    var startTime: Date
    var includesEndTime: Bool
    var endTime: Date
    private(set) var savedSchedule: Schedule

    init(todo: TodoRecordSnapshot, now: Date = .now) {
        scheduledDate = todo.scheduledDate
        includesTime = todo.includesTime
        startTime = todo.includesTime ? todo.scheduledDate : now
        includesEndTime = todo.endDate != nil
        endTime = todo.endDate
            ?? Calendar.autoupdatingCurrent.date(byAdding: .hour, value: 1, to: startTime)
            ?? startTime
        savedSchedule = Schedule(
            date: todo.scheduledDate,
            includesTime: todo.includesTime,
            endDate: todo.endDate
        )
    }

    var schedule: Schedule {
        Schedule(
            date: includesTime
                ? ScheduleDateTime.combining(scheduledDate, with: startTime)
                : Calendar.autoupdatingCurrent.startOfDay(for: scheduledDate),
            includesTime: includesTime,
            endDate: includesTime && includesEndTime
                ? ScheduleDateTime.combining(scheduledDate, with: endTime) : nil
        )
    }

    mutating func save(_ commit: (Schedule) throws -> Void) throws {
        let value = schedule
        guard value != savedSchedule else { return }
        try commit(value)
        savedSchedule = value
    }
}
