import Foundation

struct RecurrenceFormState: Equatable {
    var isEnabled: Bool
    var mode: RecurrenceMode
    var unit: RecurrenceUnit
    var interval: Int
    var anchors: Set<Int>
    var reference: Date?
    var repeatUntil: Date?

    static let disabled = RecurrenceFormState(
        isEnabled: false,
        mode: .absolute,
        unit: .day,
        interval: 1,
        anchors: [],
        reference: nil,
        repeatUntil: nil
    )

    static func enabled(
        referenceDate: Date,
        calendar: Calendar = .autoupdatingCurrent
    ) -> RecurrenceFormState {
        RecurrenceFormState(
            isEnabled: true,
            mode: .absolute,
            unit: .day,
            interval: 1,
            anchors: [],
            reference: calendar.startOfDay(for: referenceDate),
            repeatUntil: nil
        )
    }

    static func existing(
        _ template: RecurrenceTemplateRecordSnapshot,
        calendar: Calendar = .autoupdatingCurrent
    ) throws -> RecurrenceFormState {
        guard let mode = RecurrenceMode(rawValue: template.modeRawValue) else {
            throw RecurrencePersistenceError.invalidStoredMode(
                template.modeRawValue
            )
        }
        guard let unit = RecurrenceUnit(rawValue: template.unitRawValue) else {
            throw RecurrencePersistenceError.invalidStoredUnit(
                template.unitRawValue
            )
        }
        let rule: RecurrenceRule
        switch mode {
        case .relative:
            rule = try RecurrenceRule.relative(
                every: template.interval,
                unit: unit,
                repeatUntil: template.repeatUntil,
                calendar: calendar
            )
        case .absolute:
            guard let reference = template.reference else {
                throw RecurrenceError.missingReference
            }
            rule = try RecurrenceRule.absolute(
                every: template.interval,
                unit: unit,
                anchors: template.anchors,
                reference: reference,
                repeatUntil: template.repeatUntil,
                calendar: calendar
            )
        }
        return RecurrenceFormState(
            isEnabled: true,
            mode: rule.mode,
            unit: rule.unit,
            interval: rule.interval,
            anchors: Set(rule.anchors),
            reference: rule.reference,
            repeatUntil: rule.repeatUntil
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
        case .day, .year:
            return anchors.isEmpty
        case .week:
            return !anchors.isEmpty && anchors.allSatisfy((0...6).contains)
        case .month:
            return !anchors.isEmpty && anchors.allSatisfy((0...30).contains)
        }
    }

    mutating func setEnabled(
        _ enabled: Bool,
        referenceDate: Date,
        calendar: Calendar = .autoupdatingCurrent
    ) {
        guard enabled else {
            self = .disabled
            return
        }

        if !isEnabled {
            self = .enabled(
                referenceDate: referenceDate,
                calendar: calendar
            )
        }
        prepare(
            referenceDate: referenceDate,
            calendar: calendar
        )
    }

    mutating func prepare(
        referenceDate: Date,
        calendar: Calendar = .autoupdatingCurrent
    ) {
        guard isEnabled else {
            return
        }
        normalizeAnchors(
            referenceDate: referenceDate,
            calendar: calendar
        )
    }

    mutating func selectMode(
        _ newMode: RecurrenceMode,
        referenceDate: Date,
        calendar: Calendar = .autoupdatingCurrent
    ) {
        mode = newMode
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

    mutating func setRepeatUntilEnabled(
        _ enabled: Bool,
        referenceDate: Date,
        calendar: Calendar = .autoupdatingCurrent
    ) {
        guard enabled else {
            repeatUntil = nil
            return
        }
        guard repeatUntil == nil else { return }

        let start = calendar.startOfDay(for: referenceDate)
        repeatUntil = calendar.date(
            byAdding: .month,
            value: 1,
            to: start
        ) ?? start
    }

    mutating func setRepeatUntil(
        _ date: Date,
        referenceDate: Date,
        calendar: Calendar = .autoupdatingCurrent
    ) {
        let minimum = calendar.startOfDay(for: referenceDate)
        repeatUntil = max(calendar.startOfDay(for: date), minimum)
    }

    /// Creation forms call this when their item's date changes. Existing
    /// templates deliberately do not: their normalized reference defines the
    /// established absolute cadence.
    mutating func rebaseReference(
        to referenceDate: Date,
        calendar: Calendar = .autoupdatingCurrent
    ) {
        guard isEnabled && mode == .absolute else {
            clampRepeatUntil(
                to: referenceDate,
                calendar: calendar
            )
            return
        }
        reference = calendar.startOfDay(for: referenceDate)
        clampRepeatUntil(
            to: referenceDate,
            calendar: calendar
        )
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
                unit: unit,
                repeatUntil: repeatUntil,
                calendar: calendar
            )
        case .absolute:
            return try RecurrenceRule.absolute(
                every: interval,
                unit: unit,
                anchors: anchors.sorted(),
                reference: reference ?? referenceDate,
                repeatUntil: repeatUntil,
                calendar: calendar
            )
        }
    }

    private mutating func clampRepeatUntil(
        to referenceDate: Date,
        calendar: Calendar
    ) {
        guard let repeatUntil else { return }
        let minimum = calendar.startOfDay(for: referenceDate)
        if repeatUntil < minimum {
            self.repeatUntil = minimum
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
        case .day, .year:
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
        case .absolute: "Scheduled"
        case .relative: "On completion"
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
        case .year: "year"
        }
    }

    var pluralTitle: String {
        switch self {
        case .day: "days"
        case .week: "weeks"
        case .month: "months"
        case .year: "years"
        }
    }
}
