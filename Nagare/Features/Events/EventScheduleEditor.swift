import SwiftData
import SwiftUI

struct EventScheduleEditor: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext

    let event: Event

    @State private var scheduledDate: Date
    @State private var startTime: Date
    @State private var includesEndTime: Bool
    @State private var endTime: Date
    @State private var errorMessage: String?

    init(event: Event) {
        self.event = event
        _scheduledDate = State(initialValue: event.startDate)
        _startTime = State(initialValue: event.startDate)
        _includesEndTime = State(initialValue: event.endDate != nil)
        _endTime = State(
            initialValue: event.endDate
                ?? Calendar.autoupdatingCurrent.date(byAdding: .hour, value: 1, to: event.startDate)
                ?? event.startDate
        )
    }

    private var startDate: Date {
        date(on: scheduledDate, withTimeFrom: startTime)
    }

    private var endDate: Date? {
        guard includesEndTime else {
            return nil
        }
        return date(on: scheduledDate, withTimeFrom: endTime)
    }

    private var isScheduleValid: Bool {
        guard let endDate else {
            return true
        }
        return endDate > startDate
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    DatePicker(
                        "Date",
                        selection: $scheduledDate,
                        in: Calendar.autoupdatingCurrent.startOfDay(for: .now)...,
                        displayedComponents: .date
                    )

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
                } footer: {
                    if !isScheduleValid {
                        Text("The end time must be later than the start time.")
                        .foregroundStyle(.red)
                    }
                }
            }
            .navigationTitle("Change Schedule")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        dismiss()
                    }
                }

                ToolbarItem(placement: .confirmationAction) {
                    Button(action: save) {
                        Label("Save Schedule", systemImage: "checkmark")
                            .labelStyle(.iconOnly)
                    }
                    .tint(.accentColor)
                    .disabled(!isScheduleValid)
                }
            }
            .alert("Schedule Couldn't Be Changed", isPresented: isShowingError) {
                Button("OK", role: .cancel) {
                    errorMessage = nil
                }
            } message: {
                Text(errorMessage ?? "An unknown error occurred.")
            }
        }
    }

    private var isShowingError: Binding<Bool> {
        Binding(
            get: { errorMessage != nil },
            set: { isPresented in
                if !isPresented {
                    errorMessage = nil
                }
            }
        )
    }

    private func save() {
        guard isScheduleValid else {
            return
        }

        do {
            let calendar = Calendar.autoupdatingCurrent
            if !calendar.isDate(event.startDate, inSameDayAs: startDate) {
                event.sortOrder = try ItemOrdering.nextSortOrder(
                    on: startDate,
                    in: modelContext,
                    calendar: calendar
                )
            }
            event.startDate = startDate
            event.endDate = endDate
            try modelContext.save()
            dismiss()
        } catch {
            modelContext.rollback()
            errorMessage = error.localizedDescription
        }
    }

    private func date(on day: Date, withTimeFrom time: Date) -> Date {
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
