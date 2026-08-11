import SwiftData
import SwiftUI

struct TodoDateEditor: View {
    @Environment(\.modelContext) private var modelContext

    let todo: Todo

    @State private var scheduledDate: Date
    @State private var errorMessage: String?

    init(todo: Todo) {
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
        .padding()
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
            try ItemOrdering.move(
                [.todo(todo.id)],
                to: newDate,
                before: nil,
                in: modelContext,
                calendar: calendar
            )
        } catch {
            modelContext.rollback()
            scheduledDate = todo.scheduledDate
            errorMessage = error.localizedDescription
        }
    }
}
