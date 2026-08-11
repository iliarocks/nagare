import SwiftUI

struct ScheduleFields: View {
    @Binding var date: Date
    @Binding var startTime: Date
    @Binding var includesEndTime: Bool
    @Binding var endTime: Date

    var body: some View {
        DatePicker(
            "Date",
            selection: $date,
            in: Calendar.autoupdatingCurrent.startOfDay(for: .now)...,
            displayedComponents: .date
        )
        .accessibilityIdentifier("Schedule Date Picker")

        LabeledContent("Time") {
            HStack(spacing: 8) {
                DatePicker(
                    "Start Time",
                    selection: $startTime,
                    displayedComponents: .hourAndMinute
                )
                .labelsHidden()

                if includesEndTime {
                    Text("–")
                        .foregroundStyle(.secondary)

                    DatePicker(
                        "End Time",
                        selection: $endTime,
                        displayedComponents: .hourAndMinute
                    )
                    .labelsHidden()
                }

                Button {
                    includesEndTime.toggle()
                } label: {
                    Label(
                        includesEndTime ? "Remove End Time" : "Add End Time",
                        systemImage: includesEndTime ? "minus.circle.fill" : "plus.circle"
                    )
                    .labelStyle(.iconOnly)
                }
                .buttonStyle(.plain)
            }
        }
    }
}

enum ScheduleDateTime {
    static func combining(_ day: Date, with time: Date) -> Date {
        let calendar = Calendar.autoupdatingCurrent
        let timeComponents = calendar.dateComponents([.hour, .minute], from: time)

        return calendar.date(
            bySettingHour: timeComponents.hour ?? 0,
            minute: timeComponents.minute ?? 0,
            second: 0,
            of: day
        ) ?? day
    }
}
