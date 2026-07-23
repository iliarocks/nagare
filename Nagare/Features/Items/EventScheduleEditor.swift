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
        _scheduledDate = State(initialValue: event.scheduledDate)
        _startTime = State(initialValue: event.scheduledDate)
        _includesEndTime = State(initialValue: event.endDate != nil)
        _endTime = State(
            initialValue: event.endDate
                ?? Calendar.autoupdatingCurrent.date(
                    byAdding: .hour,
                    value: 1,
                    to: event.scheduledDate
                )
                ?? event.scheduledDate
        )
    }

    private var eventScheduledDate: Date {
        ScheduleDateTime.combining(scheduledDate, with: startTime)
    }

    private var endDate: Date? {
        guard includesEndTime else {
            return nil
        }
        return ScheduleDateTime.combining(scheduledDate, with: endTime)
    }

    private var isScheduleValid: Bool {
        guard let endDate else {
            return true
        }
        return endDate > eventScheduledDate
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    ScheduleFields(
                        date: $scheduledDate,
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
            if !calendar.isDate(event.scheduledDate, inSameDayAs: eventScheduledDate) {
                event.order = try ItemOrdering.nextOrder(in: modelContext)
            }
            event.scheduledDate = eventScheduledDate
            event.endDate = endDate
            try modelContext.save()
            dismiss()
        } catch {
            modelContext.rollback()
            errorMessage = error.localizedDescription
        }
    }

}
