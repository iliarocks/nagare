import Foundation

typealias SwiftDataItem = Todo

extension Todo {
    var snapshot: ItemSnapshot {
        ItemSnapshot(
            id: id,
            scheduledDate: scheduledDate,
            includesTime: includesTime,
            endDate: endDate,
            completedAt: completedAt,
            createdAt: createdAt,
            order: order,
            projectID: project?.id,
            projectOrder: projectOrder
        )
    }

    func applyOrder(_ newOrder: String) {
        order = newOrder
    }

    func applyProjectOrder(_ newOrder: String?) {
        projectOrder = newOrder
    }

    func applyProject(_ newProject: Project?) {
        project = newProject
    }

    func applySchedule(scheduledDate: Date, endDate: Date?) {
        self.scheduledDate = scheduledDate
        self.endDate = includesTime ? endDate : nil
    }

    func move(to day: Date, calendar: Calendar = .autoupdatingCurrent) {
        let destinationDay = calendar.startOfDay(for: day)
        guard includesTime else {
            scheduledDate = destinationDay
            endDate = nil
            return
        }

        let duration = endDate.map { $0.timeIntervalSince(scheduledDate) }
        let time = calendar.dateComponents(
            [.hour, .minute, .second],
            from: scheduledDate
        )
        let newStart = calendar.date(
            bySettingHour: time.hour ?? 0,
            minute: time.minute ?? 0,
            second: time.second ?? 0,
            of: destinationDay
        ) ?? destinationDay

        scheduledDate = newStart
        endDate = duration.map { newStart.addingTimeInterval($0) }
    }

    @MainActor
    static func ordered(_ todos: [Todo]) -> [Todo] {
        todos.sorted {
            if $0.order != $1.order { return $0.order < $1.order }
            return $0.id.uuidString < $1.id.uuidString
        }
    }

    @MainActor
    static func orderedInProject(_ todos: [Todo]) -> [Todo] {
        todos.sorted {
            switch ($0.projectOrder, $1.projectOrder) {
            case let (.some(first), .some(second)) where first != second:
                return first < second
            case (.some, .none):
                return true
            case (.none, .some):
                return false
            default:
                return $0.id.uuidString < $1.id.uuidString
            }
        }
    }
}
