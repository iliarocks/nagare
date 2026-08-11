import Foundation

struct VirtualItemID: Hashable {
    let templateID: UUID
    let date: Date
}

struct VirtualItem: Identifiable {
    let template: RecurrenceTemplate
    let date: Date
    let startDate: Date?
    let endDate: Date?

    var id: VirtualItemID {
        VirtualItemID(templateID: template.id, date: date)
    }

    var itemType: RecurrenceItemType? {
        template.itemType
    }

    var order: String {
        switch template.itemType {
        case .todo:
            template.todoOccurrences.first {
                $0.id == template.currentItemID && $0.completedAt == nil
            }?.order ?? ""
        case .event:
            template.eventOccurrences.first {
                $0.id == template.currentItemID
            }?.order ?? ""
        case nil:
            ""
        }
    }
}

struct RecurrenceProjectionRevision: Equatable {
    let id: UUID
    let itemTypeRawValue: String
    let modeRawValue: String
    let unitRawValue: String
    let interval: Int
    let anchors: [Int]
    let reference: Date?
    let startTimeSeconds: Int?
    let endTimeSeconds: Int?
    let currentItemID: UUID
    let currentSequence: Int
    let currentDate: Date?

    init(_ template: RecurrenceTemplate) {
        id = template.id
        itemTypeRawValue = template.itemTypeRawValue
        modeRawValue = template.modeRawValue
        unitRawValue = template.unitRawValue
        interval = template.interval
        anchors = template.anchors
        reference = template.reference
        startTimeSeconds = template.startTimeSeconds
        endTimeSeconds = template.endTimeSeconds
        currentItemID = template.currentItemID
        currentSequence = template.currentSequence

        switch template.itemType {
        case .todo:
            currentDate = template.todoOccurrences.first {
                $0.id == template.currentItemID && $0.completedAt == nil
            }?.scheduledDate
        case .event:
            currentDate = template.eventOccurrences.first {
                $0.id == template.currentItemID
            }?.scheduledDate
        case nil:
            currentDate = nil
        }
    }
}

enum VirtualItemProjection {
    static func generate(
        from templates: [RecurrenceTemplate],
        starting startDate: Date,
        through horizon: Date,
        calendar: Calendar = .autoupdatingCurrent
    ) throws -> [VirtualItem] {
        var items: [VirtualItem] = []
        for template in templates {
            items.append(
                contentsOf: try generate(
                    from: template,
                    starting: startDate,
                    through: horizon,
                    calendar: calendar
                )
            )
        }
        return items.sorted {
            if $0.date != $1.date {
                return $0.date < $1.date
            }
            return $0.template.id.uuidString < $1.template.id.uuidString
        }
    }

    static func generate(
        from template: RecurrenceTemplate,
        starting startDate: Date,
        through horizon: Date,
        calendar: Calendar = .autoupdatingCurrent
    ) throws -> [VirtualItem] {
        let currentDate = try currentDate(for: template)
        let rule = try template.rule(calendar: calendar)
        let dates = try RecurrenceCalculator.virtualDates(
            after: currentDate,
            using: rule,
            absoluteThrough: horizon,
            calendar: calendar
        )
        let firstVisibleDay = calendar.startOfDay(for: startDate)

        return try dates.compactMap { date in
            let day = calendar.startOfDay(for: date)
            guard day >= firstVisibleDay else {
                return nil
            }

            switch template.itemType {
            case .todo:
                return VirtualItem(
                    template: template,
                    date: day,
                    startDate: nil,
                    endDate: nil
                )
            case .event:
                guard let startSeconds = template.startTimeSeconds else {
                    throw VirtualItemProjectionError.missingEventStartTime
                }
                let start = try applying(
                    seconds: startSeconds,
                    to: day,
                    calendar: calendar
                )
                let end = try template.endTimeSeconds.map {
                    try applying(
                        seconds: $0,
                        to: day,
                        calendar: calendar
                    )
                }
                return VirtualItem(
                    template: template,
                    date: day,
                    startDate: start,
                    endDate: end
                )
            case nil:
                throw VirtualItemProjectionError.invalidItemType(
                    template.itemTypeRawValue
                )
            }
        }
    }

    private static func currentDate(
        for template: RecurrenceTemplate
    ) throws -> Date {
        switch template.itemType {
        case .todo:
            guard let todo = template.todoOccurrences.first(where: {
                $0.id == template.currentItemID && $0.completedAt == nil
            }) else {
                throw VirtualItemProjectionError.missingCurrentOccurrence
            }
            return todo.scheduledDate
        case .event:
            guard let event = template.eventOccurrences.first(where: {
                $0.id == template.currentItemID
            }) else {
                throw VirtualItemProjectionError.missingCurrentOccurrence
            }
            return event.scheduledDate
        case nil:
            throw VirtualItemProjectionError.invalidItemType(
                template.itemTypeRawValue
            )
        }
    }

    private static func applying(
        seconds: Int,
        to day: Date,
        calendar: Calendar
    ) throws -> Date {
        guard (0..<86_400).contains(seconds) else {
            throw VirtualItemProjectionError.invalidEventTime(seconds)
        }
        let hour = seconds / 3_600
        let minute = seconds % 3_600 / 60
        let second = seconds % 60
        guard let result = calendar.date(
            bySettingHour: hour,
            minute: minute,
            second: second,
            of: day
        ) else {
            throw VirtualItemProjectionError.dateCalculationFailed
        }
        return result
    }
}

enum VirtualItemProjectionError: Error, LocalizedError {
    case missingCurrentOccurrence
    case invalidItemType(String)
    case missingEventStartTime
    case invalidEventTime(Int)
    case dateCalculationFailed
    case horizonCalculationFailed

    var errorDescription: String? {
        switch self {
        case .missingCurrentOccurrence:
            "A recurrence template has no matching current occurrence. (VIRTUAL-001)"
        case .invalidItemType(let value):
            "A recurrence template contains the unknown item type “\(value)”. (VIRTUAL-002)"
        case .missingEventStartTime:
            "A virtual Event is missing its start time. (VIRTUAL-003)"
        case .invalidEventTime(let seconds):
            "A virtual Event contains the invalid wall time \(seconds). (VIRTUAL-004)"
        case .dateCalculationFailed:
            "Nagare couldn't calculate a virtual Event time. (VIRTUAL-005)"
        case .horizonCalculationFailed:
            "Nagare couldn't calculate the Upcoming recurrence horizon. (VIRTUAL-006)"
        }
    }
}
