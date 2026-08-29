import SwiftUI

struct TodoScheduleEditor: View {
    @NagareDataStoreEnvironment private var dataStore

    let todo: TodoRecordSnapshot

    @State private var scheduledDate: Date
    @State private var includesTime: Bool
    @State private var startTime: Date
    @State private var includesEndTime: Bool
    @State private var endTime: Date
    @State private var errorMessage: String?

    init(todo: TodoRecordSnapshot) {
        self.todo = todo
        let initialStartTime = todo.includesTime
            ? todo.scheduledDate
            : Date.now
        _scheduledDate = State(initialValue: todo.scheduledDate)
        _includesTime = State(initialValue: todo.includesTime)
        _startTime = State(initialValue: initialStartTime)
        _includesEndTime = State(initialValue: todo.endDate != nil)
        _endTime = State(
            initialValue: todo.endDate
                ?? Calendar.autoupdatingCurrent.date(
                    byAdding: .hour,
                    value: 1,
                    to: initialStartTime
                )
                ?? initialStartTime
        )
    }

    private var resolvedScheduledDate: Date {
        if includesTime {
            return ScheduleDateTime.combining(scheduledDate, with: startTime)
        }
        return Calendar.autoupdatingCurrent.startOfDay(for: scheduledDate)
    }

    private var resolvedEndDate: Date? {
        guard includesTime && includesEndTime else { return nil }
        return ScheduleDateTime.combining(scheduledDate, with: endTime)
    }

    var body: some View {
        ScheduleEditorForm(
            scheduledDate: $scheduledDate,
            includesTime: $includesTime,
            startTime: $startTime,
            includesEndTime: $includesEndTime,
            endTime: $endTime
        )
        .onChange(of: scheduledDate) { save() }
        .onChange(of: includesTime) { save() }
        .onChange(of: startTime) { save() }
        .onChange(of: includesEndTime) { save() }
        .onChange(of: endTime) { save() }
        .alert("Schedule Couldn't Be Changed", isPresented: isShowingError) {
            Button("OK", role: .cancel) { errorMessage = nil }
        } message: {
            Text(errorMessage ?? "An unknown error occurred.")
        }
    }

    private var isShowingError: Binding<Bool> {
        Binding(
            get: { errorMessage != nil },
            set: { if !$0 { errorMessage = nil } }
        )
    }

    private func save() {
        guard todo.scheduledDate != resolvedScheduledDate
            || todo.includesTime != includesTime
            || todo.endDate != resolvedEndDate else {
            return
        }
        do {
            try dataStore.updateTodoSchedule(
                todo.id,
                scheduledDate: resolvedScheduledDate,
                includesTime: includesTime,
                endDate: resolvedEndDate
            )
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}
