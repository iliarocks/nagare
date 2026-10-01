import SwiftUI

struct TodoScheduleEditor: View {
    @NagareDataStoreEnvironment private var dataStore

    let todo: TodoRecordSnapshot

    @State private var draft: TodoScheduleDraft
    @State private var errorMessage: String?

    init(todo: TodoRecordSnapshot) {
        self.todo = todo
        _draft = State(initialValue: TodoScheduleDraft(todo: todo))
    }

    var body: some View {
        ScheduleEditorForm(
            scheduledDate: $draft.scheduledDate,
            includesTime: $draft.includesTime,
            startTime: $draft.startTime,
            includesEndTime: $draft.includesEndTime,
            endTime: $draft.endTime
        )
        .onChange(of: draft.schedule) { save() }
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
        do {
            try draft.save { schedule in
                try dataStore.updateTodoSchedule(
                    todo.id,
                    scheduledDate: schedule.date,
                    includesTime: schedule.includesTime,
                    endDate: schedule.endDate
                )
            }
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}
