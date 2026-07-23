import Foundation

enum RecurrenceMode: String, CaseIterable, Codable, Sendable {
    case relative
    case absolute
}

enum RecurrenceUnit: String, CaseIterable, Codable, Sendable {
    case day
    case week
    case month
}

struct RecurrenceRule: Equatable, Sendable {
    let mode: RecurrenceMode
    let unit: RecurrenceUnit
    let interval: Int
    let anchors: [Int]
    let reference: Date?

    private init(
        mode: RecurrenceMode,
        unit: RecurrenceUnit,
        interval: Int,
        anchors: [Int],
        reference: Date?
    ) {
        self.mode = mode
        self.unit = unit
        self.interval = interval
        self.anchors = anchors
        self.reference = reference
    }

    static func relative(
        every interval: Int,
        unit: RecurrenceUnit
    ) throws -> RecurrenceRule {
        guard interval > 0 else {
            throw RecurrenceError.invalidInterval(interval)
        }

        return RecurrenceRule(
            mode: .relative,
            unit: unit,
            interval: interval,
            anchors: [],
            reference: nil
        )
    }

    static func absolute(
        every interval: Int,
        unit: RecurrenceUnit,
        anchors: [Int] = [],
        reference: Date,
        calendar: Calendar = .autoupdatingCurrent
    ) throws -> RecurrenceRule {
        guard interval > 0 else {
            throw RecurrenceError.invalidInterval(interval)
        }

        let canonicalAnchors: [Int]
        switch unit {
        case .day:
            guard anchors.isEmpty else {
                throw RecurrenceError.unexpectedAnchors(unit)
            }
            canonicalAnchors = []

        case .week:
            canonicalAnchors = try validate(
                anchors: anchors,
                for: unit,
                validRange: 0...6
            )

        case .month:
            canonicalAnchors = try validate(
                anchors: anchors,
                for: unit,
                validRange: 0...30
            )
        }

        return RecurrenceRule(
            mode: .absolute,
            unit: unit,
            interval: interval,
            anchors: canonicalAnchors,
            reference: try RecurrenceCalculator.normalizedReference(
                reference,
                for: unit,
                calendar: calendar
            )
        )
    }

    private static func validate(
        anchors: [Int],
        for unit: RecurrenceUnit,
        validRange: ClosedRange<Int>
    ) throws -> [Int] {
        guard !anchors.isEmpty else {
            throw RecurrenceError.missingAnchors(unit)
        }

        for anchor in anchors where !validRange.contains(anchor) {
            throw RecurrenceError.invalidAnchor(
                anchor,
                unit: unit,
                validRange: validRange
            )
        }

        guard Set(anchors).count == anchors.count else {
            throw RecurrenceError.duplicateAnchors(unit)
        }

        return anchors.sorted()
    }
}

enum RecurrenceCalculator {
    static func normalizedReference(
        _ reference: Date,
        for unit: RecurrenceUnit,
        calendar: Calendar = .autoupdatingCurrent
    ) throws -> Date {
        switch unit {
        case .day:
            return calendar.startOfDay(for: reference)
        case .week:
            return try startOfMonday(containing: reference, calendar: calendar)
        case .month:
            return try startOfMonth(containing: reference, calendar: calendar)
        }
    }

    static func nextDate(
        after date: Date,
        using rule: RecurrenceRule,
        calendar: Calendar = .autoupdatingCurrent
    ) throws -> Date {
        let date = calendar.startOfDay(for: date)

        switch rule.mode {
        case .relative:
            return try advance(
                date,
                by: rule.interval,
                unit: rule.unit,
                calendar: calendar
            )

        case .absolute:
            guard let reference = rule.reference else {
                throw RecurrenceError.missingReference
            }

            switch rule.unit {
            case .day:
                return try nextAbsoluteDay(
                    after: date,
                    reference: reference,
                    interval: rule.interval,
                    calendar: calendar
                )
            case .week:
                return try nextAbsoluteWeekDate(
                    after: date,
                    reference: reference,
                    interval: rule.interval,
                    anchors: rule.anchors,
                    calendar: calendar
                )
            case .month:
                return try nextAbsoluteMonthDate(
                    after: date,
                    reference: reference,
                    interval: rule.interval,
                    anchors: rule.anchors,
                    calendar: calendar
                )
            }
        }
    }

    /// Relative rules expose exactly one next virtual date. Absolute rules
    /// expose every virtual date through the inclusive display horizon.
    static func virtualDates(
        after currentDate: Date,
        using rule: RecurrenceRule,
        absoluteThrough horizon: Date,
        calendar: Calendar = .autoupdatingCurrent,
        maximumCount: Int = 10_000
    ) throws -> [Date] {
        guard maximumCount > 0 else {
            throw RecurrenceError.invalidProjectionLimit(maximumCount)
        }

        let first = try nextDate(
            after: currentDate,
            using: rule,
            calendar: calendar
        )

        if rule.mode == .relative {
            return [first]
        }

        let horizon = calendar.startOfDay(for: horizon)
        guard first <= horizon else {
            return []
        }

        var dates: [Date] = []
        var candidate = first

        while candidate <= horizon {
            guard dates.count < maximumCount else {
                throw RecurrenceError.projectionLimitExceeded(maximumCount)
            }

            dates.append(candidate)
            let next = try nextDate(
                after: candidate,
                using: rule,
                calendar: calendar
            )
            guard next > candidate else {
                throw RecurrenceError.nonAdvancingSchedule
            }
            candidate = next
        }

        return dates
    }

    private static func advance(
        _ date: Date,
        by interval: Int,
        unit: RecurrenceUnit,
        calendar: Calendar
    ) throws -> Date {
        switch unit {
        case .day:
            return try adding(
                .day,
                value: interval,
                to: date,
                calendar: calendar
            )
        case .week:
            return try adding(
                .weekOfYear,
                value: interval,
                to: date,
                calendar: calendar
            )
        case .month:
            return try addingMonths(
                interval,
                to: date,
                calendar: calendar
            )
        }
    }

    private static func nextAbsoluteDay(
        after date: Date,
        reference: Date,
        interval: Int,
        calendar: Calendar
    ) throws -> Date {
        let reference = calendar.startOfDay(for: reference)
        guard date >= reference else {
            return reference
        }

        guard let elapsedDays = calendar.dateComponents(
            [.day],
            from: reference,
            to: date
        ).day else {
            throw RecurrenceError.dateCalculationFailed
        }

        let intervalsElapsed = elapsedDays / interval
        return try adding(
            .day,
            value: (intervalsElapsed + 1) * interval,
            to: reference,
            calendar: calendar
        )
    }

    private static func nextAbsoluteWeekDate(
        after date: Date,
        reference: Date,
        interval: Int,
        anchors: [Int],
        calendar: Calendar
    ) throws -> Date {
        guard let firstAnchor = anchors.first else {
            throw RecurrenceError.missingAnchors(.week)
        }

        let currentPeriod = try startOfMonday(
            containing: date,
            calendar: calendar
        )
        let referencePeriod = try startOfMonday(
            containing: reference,
            calendar: calendar
        )

        if currentPeriod < referencePeriod {
            return try adding(
                .day,
                value: firstAnchor,
                to: referencePeriod,
                calendar: calendar
            )
        }

        guard let elapsedDays = calendar.dateComponents(
            [.day],
            from: referencePeriod,
            to: currentPeriod
        ).day else {
            throw RecurrenceError.dateCalculationFailed
        }
        let elapsedWeeks = elapsedDays / 7
        let remainder = positiveRemainder(elapsedWeeks, dividedBy: interval)

        if remainder == 0 {
            for anchor in anchors {
                let candidate = try adding(
                    .day,
                    value: anchor,
                    to: currentPeriod,
                    calendar: calendar
                )
                if candidate > date {
                    return candidate
                }
            }
        }

        let weeksToAdvance = remainder == 0 ? interval : interval - remainder
        let nextPeriod = try adding(
            .weekOfYear,
            value: weeksToAdvance,
            to: currentPeriod,
            calendar: calendar
        )
        return try adding(
            .day,
            value: firstAnchor,
            to: nextPeriod,
            calendar: calendar
        )
    }

    private static func nextAbsoluteMonthDate(
        after date: Date,
        reference: Date,
        interval: Int,
        anchors: [Int],
        calendar: Calendar
    ) throws -> Date {
        guard let firstAnchor = anchors.first else {
            throw RecurrenceError.missingAnchors(.month)
        }

        let currentPeriod = try startOfMonth(
            containing: date,
            calendar: calendar
        )
        let referencePeriod = try startOfMonth(
            containing: reference,
            calendar: calendar
        )

        if currentPeriod < referencePeriod {
            return try dateInMonth(
                inMonthStarting: referencePeriod,
                zeroBasedDay: firstAnchor,
                calendar: calendar
            )
        }

        guard let elapsedMonths = calendar.dateComponents(
            [.month],
            from: referencePeriod,
            to: currentPeriod
        ).month else {
            throw RecurrenceError.dateCalculationFailed
        }
        let remainder = positiveRemainder(
            elapsedMonths,
            dividedBy: interval
        )

        if remainder == 0 {
            for anchor in anchors {
                let candidate = try dateInMonth(
                    inMonthStarting: currentPeriod,
                    zeroBasedDay: anchor,
                    calendar: calendar
                )
                if candidate > date {
                    return candidate
                }
            }
        }

        let monthsToAdvance = remainder == 0 ? interval : interval - remainder
        let nextPeriod = try adding(
            .month,
            value: monthsToAdvance,
            to: currentPeriod,
            calendar: calendar
        )
        return try dateInMonth(
            inMonthStarting: nextPeriod,
            zeroBasedDay: firstAnchor,
            calendar: calendar
        )
    }

    private static func startOfMonday(
        containing date: Date,
        calendar: Calendar
    ) throws -> Date {
        let day = calendar.startOfDay(for: date)
        let weekday = calendar.component(.weekday, from: day)
        let daysSinceMonday = (weekday + 5) % 7
        return try adding(
            .day,
            value: -daysSinceMonday,
            to: day,
            calendar: calendar
        )
    }

    private static func startOfMonth(
        containing date: Date,
        calendar: Calendar
    ) throws -> Date {
        var components = calendar.dateComponents(
            [.era, .year, .month],
            from: date
        )
        components.day = 1
        components.hour = 0
        components.minute = 0
        components.second = 0

        guard let result = calendar.date(from: components) else {
            throw RecurrenceError.dateCalculationFailed
        }
        return result
    }

    private static func addingMonths(
        _ months: Int,
        to date: Date,
        calendar: Calendar
    ) throws -> Date {
        let originalDay = calendar.component(.day, from: date)
        let currentMonth = try startOfMonth(
            containing: date,
            calendar: calendar
        )
        let targetMonth = try adding(
            .month,
            value: months,
            to: currentMonth,
            calendar: calendar
        )
        return try dateInMonth(
            inMonthStarting: targetMonth,
            zeroBasedDay: originalDay - 1,
            calendar: calendar
        )
    }

    private static func dateInMonth(
        inMonthStarting month: Date,
        zeroBasedDay: Int,
        calendar: Calendar
    ) throws -> Date {
        guard let dayRange = calendar.range(
            of: .day,
            in: .month,
            for: month
        ) else {
            throw RecurrenceError.dateCalculationFailed
        }

        var components = calendar.dateComponents(
            [.era, .year, .month],
            from: month
        )
        components.day = min(zeroBasedDay + 1, dayRange.count)
        components.hour = 0
        components.minute = 0
        components.second = 0

        guard let result = calendar.date(from: components) else {
            throw RecurrenceError.dateCalculationFailed
        }
        return result
    }

    private static func adding(
        _ component: Calendar.Component,
        value: Int,
        to date: Date,
        calendar: Calendar
    ) throws -> Date {
        guard let result = calendar.date(
            byAdding: component,
            value: value,
            to: date
        ) else {
            throw RecurrenceError.dateCalculationFailed
        }
        return calendar.startOfDay(for: result)
    }

    private static func positiveRemainder(
        _ value: Int,
        dividedBy divisor: Int
    ) -> Int {
        ((value % divisor) + divisor) % divisor
    }
}

enum RecurrenceError: Error, Equatable, LocalizedError {
    case invalidInterval(Int)
    case missingAnchors(RecurrenceUnit)
    case unexpectedAnchors(RecurrenceUnit)
    case invalidAnchor(
        Int,
        unit: RecurrenceUnit,
        validRange: ClosedRange<Int>
    )
    case duplicateAnchors(RecurrenceUnit)
    case missingReference
    case invalidProjectionLimit(Int)
    case projectionLimitExceeded(Int)
    case nonAdvancingSchedule
    case dateCalculationFailed

    var errorDescription: String? {
        switch self {
        case .invalidInterval(let interval):
            return "A recurrence interval must be greater than zero; received \(interval). (RECURRENCE-001)"
        case .missingAnchors(let unit):
            return "An absolute \(unit.rawValue) recurrence requires at least one anchor. (RECURRENCE-002)"
        case .unexpectedAnchors(let unit):
            return "A \(unit.rawValue) recurrence does not accept anchors. (RECURRENCE-003)"
        case .invalidAnchor(let anchor, let unit, let validRange):
            return "Anchor \(anchor) is invalid for a \(unit.rawValue) recurrence; expected \(validRange.lowerBound)...\(validRange.upperBound). (RECURRENCE-004)"
        case .duplicateAnchors(let unit):
            return "A \(unit.rawValue) recurrence contains duplicate anchors. (RECURRENCE-005)"
        case .missingReference:
            return "An absolute recurrence is missing its reference date. (RECURRENCE-006)"
        case .invalidProjectionLimit(let limit):
            return "The recurrence projection limit must be greater than zero; received \(limit). (RECURRENCE-007)"
        case .projectionLimitExceeded(let limit):
            return "Nagare stopped recurrence projection after \(limit) occurrences. (RECURRENCE-008)"
        case .nonAdvancingSchedule:
            return "The recurrence schedule did not advance to a later date. (RECURRENCE-009)"
        case .dateCalculationFailed:
            return "Nagare couldn't calculate a recurrence date. (RECURRENCE-010)"
        }
    }
}
