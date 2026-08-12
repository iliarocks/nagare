import SwiftUI

struct TodoDateEditor: View {
    @NagareDataStoreEnvironment private var dataStore

    let todo: TodoRecordSnapshot

    @State private var scheduledDate: Date
    @State private var errorMessage: String?

    init(todo: TodoRecordSnapshot) {
        self.todo = todo
        _scheduledDate = State(initialValue: todo.scheduledDate)
    }

    var body: some View {
        DatePicker(
            "Date",
            selection: $scheduledDate,
            in: Calendar.autoupdatingCurrent.startOfDay(for: .now)...,
            displayedComponents: .date
        )
        .datePickerStyle(.graphical)
        .labelsHidden()
        .nagareDetailsPanel(width: 400, height: 360)
        .onChange(of: scheduledDate) {
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
        let calendar = Calendar.autoupdatingCurrent
        let newDate = calendar.startOfDay(for: scheduledDate)
        guard !calendar.isDate(todo.scheduledDate, inSameDayAs: newDate) else {
            return
        }

        do {
            try dataStore.moveItems(
                [.todo(todo.id)],
                to: newDate,
                before: nil,
                calendar: calendar
            )
        } catch {
            scheduledDate = todo.scheduledDate
            errorMessage = error.localizedDescription
        }
    }
}
