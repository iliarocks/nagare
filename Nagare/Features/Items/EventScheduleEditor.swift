import SwiftUI

struct EventScheduleEditor: View {
    static let sheetDetent = PresentationDetent.height(230)

    @NagareDataStoreEnvironment private var dataStore

    let event: EventRecordSnapshot

    @State private var scheduledDate: Date
    @State private var startTime: Date
    @State private var includesEndTime: Bool
    @State private var endTime: Date
    @State private var errorMessage: String?

    init(event: EventRecordSnapshot) {
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
        .nagareDetailsForm(
            height: includesEndTime || !isScheduleValid ? 230 : 180
        )
        .animation(.snappy, value: includesEndTime)
        .onChange(of: scheduledDate) {
            save()
        }
        .onChange(of: startTime) {
            save()
        }
        .onChange(of: includesEndTime) {
            save()
        }
        .onChange(of: endTime) {
            save()
        }
        .alert("Details Couldn't Be Changed", isPresented: isShowingError) {
            Button("OK", role: .cancel) {
                errorMessage = nil
            }
        } message: {
            Text(errorMessage ?? "An unknown error occurred.")
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

        guard event.scheduledDate != eventScheduledDate
            || event.endDate != endDate else {
            return
        }

        do {
            try dataStore.updateEventSchedule(
                event.id,
                scheduledDate: eventScheduledDate,
                endDate: endDate
            )
        } catch {
            errorMessage = error.localizedDescription
        }
    }

}
