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
