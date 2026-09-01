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
        .animation(.snappy, value: state.repeatUntil != nil)
    }

    private var editorHeight: CGFloat {
        guard state.isEnabled else { return 120 }

#if os(macOS)
        var height: CGFloat = 290
#else
        var height: CGFloat = 230
#endif
        if state.repeatUntil != nil {
            height += 100
        }
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
        guard let next = try? RecurrenceCalculator.nextDate(
            after: date,
            using: rule,
            calendar: calendar
        ) else { return nil }
        return rule.permits(next, calendar: calendar) ? next : nil
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

}
