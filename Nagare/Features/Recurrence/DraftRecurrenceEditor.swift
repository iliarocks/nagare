import SwiftUI

struct DraftRecurrenceEditor: View {
    @Binding var state: RecurrenceFormState

    let referenceDate: Date

    var body: some View {
        Form {
            RecurrenceFields(
                state: $state,
                referenceDate: referenceDate
            )
        }
        .nagareDetailsForm(height: editorHeight)
        .scrollIndicators(.hidden)
        .animation(.snappy, value: state.mode)
        .animation(.snappy, value: state.unit)
    }

    private var editorHeight: CGFloat {
        guard state.isEnabled else { return 120 }

        var height: CGFloat = 230
        guard state.mode == .absolute else { return height }

        switch state.unit {
        case .day, .year:
            return height
        case .week:
            height += 90
        case .month:
            height += 260
        }
        return min(height, 520)
    }
}

enum RecurrencePresentation {
    static func summary(_ state: RecurrenceFormState) -> String {
        guard state.isEnabled else { return "No repeat" }
        return summary(
            unit: state.unit,
            interval: state.interval
        )
    }

    static func summary(
        _ template: RecurrenceTemplateRecordSnapshot
    ) -> String {
        guard RecurrenceMode(rawValue: template.modeRawValue) != nil,
              let unit = RecurrenceUnit(rawValue: template.unitRawValue) else {
            return "Repeat unavailable"
        }
        return summary(
            unit: unit,
            interval: template.interval
        )
    }

    static func nextDate(
        after date: Date,
        for template: RecurrenceTemplateRecordSnapshot,
        calendar: Calendar = .autoupdatingCurrent
    ) -> Date? {
        guard let form = try? RecurrenceFormState.existing(
            template,
            calendar: calendar
        ),
        let rule = try? form.rule(
            referenceDate: date,
            calendar: calendar
        ) else {
            return nil
        }
        return try? RecurrenceCalculator.nextDate(
            after: date,
            using: rule,
            calendar: calendar
        )
    }

    static func isInUpcomingRange(
        _ date: Date,
        now: Date = .now,
        calendar: Calendar = .autoupdatingCurrent
    ) -> Bool {
        let today = calendar.startOfDay(for: now)
        guard let tomorrow = calendar.date(
            byAdding: .day,
            value: 1,
            to: today
        ),
        let horizon = calendar.date(
            byAdding: .month,
            value: 2,
            to: today
        ) else {
            return false
        }
        let day = calendar.startOfDay(for: date)
        return day >= tomorrow && day <= horizon
    }

    private static func summary(
        unit: RecurrenceUnit,
        interval: Int
    ) -> String {
        interval == 1
            ? "Every \(unit.singularTitle)"
            : "Every \(interval) \(unit.pluralTitle)"
    }
}
