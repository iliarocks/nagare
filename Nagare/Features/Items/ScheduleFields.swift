import SwiftUI

struct ScheduleFields: View {
    @Binding var date: Date
    @Binding var includesTime: Bool
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
        .nagareCompactDatePickerStyle()
        .accessibilityIdentifier("Schedule Date Picker")

        TimeRangeFields(
            includesTime: $includesTime,
            startTime: $startTime,
            includesEndTime: $includesEndTime,
            endTime: $endTime
        )
    }
}

struct TimeRangeFields: View {
    @Binding var includesTime: Bool
    @Binding var startTime: Date
    @Binding var includesEndTime: Bool
    @Binding var endTime: Date

    var body: some View {
        LabeledContent {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                if includesTime {
                    DatePicker(
                        "Start Time",
                        selection: $startTime,
                        displayedComponents: .hourAndMinute
                    )
                    .nagareCompactDatePickerStyle()
                    .labelsHidden()

                    if includesEndTime {
                        Text("-")
                            .foregroundStyle(.secondary)

                        DatePicker(
                            "End Time",
                            selection: $endTime,
                            displayedComponents: .hourAndMinute
                        )
                        .nagareCompactDatePickerStyle()
                        .labelsHidden()
                    }
                } else {
                    Text("No time")
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                        .fixedSize(horizontal: true, vertical: false)
                }

                if includesTime {
                    Button(action: removeTimeComponent) {
                        Text(Image(systemName: "minus.circle.fill"))
                    }
                    .buttonStyle(.plain)
                    .font(.body)
                    .accessibilityLabel(
                        includesEndTime ? "Remove End Time" : "Remove Time"
                    )
                }

                if !includesTime || !includesEndTime {
                    Button(action: addTimeComponent) {
                        Text(Image(systemName: "plus.circle"))
                    }
                    .buttonStyle(.plain)
                    .font(.body)
                    .accessibilityLabel(
                        includesTime ? "Add End Time" : "Add Time"
                    )
                }
            }
            .frame(minHeight: 36)
        } label: {
            Text("Time")
                .frame(minHeight: 36, alignment: .center)
        }
    }

    private func addTimeComponent() {
        if includesTime {
            if wallTimeSeconds(endTime) <= wallTimeSeconds(startTime) {
                endTime = Calendar.autoupdatingCurrent.date(
                    byAdding: .hour,
                    value: 1,
                    to: startTime
                ) ?? startTime
            }
            includesEndTime = true
        } else {
            includesTime = true
        }
    }

    private func removeTimeComponent() {
        if includesEndTime {
            includesEndTime = false
        } else {
            includesTime = false
        }
    }

    private func wallTimeSeconds(_ date: Date) -> Int {
        let components = Calendar.autoupdatingCurrent.dateComponents(
            [.hour, .minute, .second],
            from: date
        )
        return (components.hour ?? 0) * 3_600
            + (components.minute ?? 0) * 60
            + (components.second ?? 0)
    }
}

struct ScheduleEditorForm: View {
    @Binding var scheduledDate: Date
    @Binding var includesTime: Bool
    @Binding var startTime: Date
    @Binding var includesEndTime: Bool
    @Binding var endTime: Date

    let isScheduleValid: Bool

    private var height: CGFloat {
        if !isScheduleValid { return 250 }
        return 200
    }

    var body: some View {
        Form {
            Section {
                ScheduleFields(
                    date: $scheduledDate,
                    includesTime: $includesTime,
                    startTime: $startTime,
                    includesEndTime: $includesEndTime,
                    endTime: $endTime
                )
            } footer: {
                if !isScheduleValid {
                    Text("The end time must be later than the start time.")
                        .foregroundStyle(.red)
                }
            }
        }
        .nagareDetailsForm(height: height)
        .nagareSheetDetents([.height(height)])
        .presentationDragIndicator(.visible)
        .animation(.snappy, value: includesTime)
        .animation(.snappy, value: includesEndTime)
        .animation(.snappy, value: isScheduleValid)
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
