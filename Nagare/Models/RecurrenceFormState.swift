import Foundation

struct RecurrenceFormState: Equatable {
    var isEnabled: Bool
    var mode: RecurrenceMode
    var unit: RecurrenceUnit
    var interval: Int
    var anchors: Set<Int>
    var reference: Date?

    static let disabled = RecurrenceFormState(
        isEnabled: false,
        mode: .absolute,
        unit: .day,
        interval: 1,
        anchors: [],
        reference: nil
    )

    static func enabled(
        for itemType: RecurrenceItemType,
        referenceDate: Date,
        calendar: Calendar = .autoupdatingCurrent
    ) -> RecurrenceFormState {
        RecurrenceFormState(
            isEnabled: true,
            mode: .absolute,
            unit: .day,
            interval: 1,
            anchors: [],
            reference: calendar.startOfDay(for: referenceDate)
        )
    }

    static func existing(
        _ template: RecurrenceTemplate,
        calendar: Calendar = .autoupdatingCurrent
    ) throws -> RecurrenceFormState {
        let rule = try template.rule(calendar: calendar)
        return RecurrenceFormState(
            isEnabled: true,
            mode: rule.mode,
            unit: rule.unit,
            interval: rule.interval,
            anchors: Set(rule.anchors),
            reference: rule.reference
        )
    }

    var isValid: Bool {
        guard !isEnabled || interval > 0 else {
            return false
        }
        guard isEnabled && mode == .absolute else {
            return true
        }

        switch unit {
        case .day:
            return anchors.isEmpty
        case .week:
            return !anchors.isEmpty && anchors.allSatisfy((0...6).contains)
        case .month:
            return !anchors.isEmpty && anchors.allSatisfy((0...30).contains)
        }
    }

    mutating func setEnabled(
        _ enabled: Bool,
        for itemType: RecurrenceItemType,
        referenceDate: Date,
        calendar: Calendar = .autoupdatingCurrent
    ) {
        guard enabled else {
            self = .disabled
            return
        }

        if !isEnabled {
            self = .enabled(
                for: itemType,
                referenceDate: referenceDate,
                calendar: calendar
            )
        }
        prepare(
            for: itemType,
            referenceDate: referenceDate,
            calendar: calendar
        )
    }

    mutating func prepare(
        for itemType: RecurrenceItemType,
        referenceDate: Date,
        calendar: Calendar = .autoupdatingCurrent
    ) {
        guard isEnabled else {
            return
        }
        if itemType == .event {
            mode = .absolute
        }
        normalizeAnchors(
            referenceDate: referenceDate,
            calendar: calendar
        )
    }

    mutating func selectMode(
        _ newMode: RecurrenceMode,
        for itemType: RecurrenceItemType,
        referenceDate: Date,
        calendar: Calendar = .autoupdatingCurrent
    ) {
        mode = itemType == .event ? .absolute : newMode
        reference = nil
        normalizeAnchors(
            referenceDate: referenceDate,
            calendar: calendar
        )
    }

    mutating func selectUnit(
        _ newUnit: RecurrenceUnit,
        referenceDate: Date,
        calendar: Calendar = .autoupdatingCurrent
    ) {
        unit = newUnit
        reference = nil
        anchors = []
        normalizeAnchors(
            referenceDate: referenceDate,
            calendar: calendar
        )
    }

    mutating func toggleAnchor(_ anchor: Int) {
        if anchors.contains(anchor) {
            anchors.remove(anchor)
        } else {
            anchors.insert(anchor)
        }
    }

    /// Creation forms call this when their item's date changes. Existing
    /// templates deliberately do not: their normalized reference defines the
    /// established absolute cadence.
    mutating func rebaseReference(
        to referenceDate: Date,
        calendar: Calendar = .autoupdatingCurrent
    ) {
        guard isEnabled && mode == .absolute else {
            return
        }
        reference = calendar.startOfDay(for: referenceDate)
    }

    func rule(
        referenceDate: Date,
        calendar: Calendar = .autoupdatingCurrent
    ) throws -> RecurrenceRule? {
        guard isEnabled else {
            return nil
        }

        switch mode {
        case .relative:
            return try RecurrenceRule.relative(
                every: interval,
                unit: unit
            )
        case .absolute:
            return try RecurrenceRule.absolute(
                every: interval,
                unit: unit,
                anchors: anchors.sorted(),
                reference: reference ?? referenceDate,
                calendar: calendar
            )
        }
    }

    private mutating func normalizeAnchors(
        referenceDate: Date,
        calendar: Calendar
    ) {
        guard mode == .absolute else {
            anchors = []
            return
        }

        switch unit {
        case .day:
            anchors = []
        case .week:
            anchors = Set(anchors.filter((0...6).contains))
            if anchors.isEmpty {
                let weekday = calendar.component(.weekday, from: referenceDate)
                anchors = [(weekday + 5) % 7]
            }
        case .month:
            anchors = Set(anchors.filter((0...30).contains))
            if anchors.isEmpty {
                anchors = [
                    min(
                        max(calendar.component(.day, from: referenceDate) - 1, 0),
                        30
                    )
                ]
            }
        }
    }
}

extension RecurrenceMode: Identifiable {
    var id: Self { self }

    var title: String {
        switch self {
        case .absolute: "On schedule"
        case .relative: "After completion"
        }
    }
}

extension RecurrenceUnit: Identifiable {
    var id: Self { self }

    var singularTitle: String {
        switch self {
        case .day: "day"
        case .week: "week"
        case .month: "month"
        }
    }

    var pluralTitle: String {
        switch self {
        case .day: "days"
        case .week: "weeks"
        case .month: "months"
        }
    }
}
