import SwiftData
import SwiftUI

struct TodoDateEditor: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext

    let todo: Todo

    @State private var scheduledDate: Date
    @State private var errorMessage: String?

    init(todo: Todo) {
        self.todo = todo
        _scheduledDate = State(initialValue: todo.scheduledDate)
    }

    var body: some View {
        NavigationStack {
            DatePicker(
                "Date",
                selection: $scheduledDate,
                in: Calendar.autoupdatingCurrent.startOfDay(for: .now)...,
                displayedComponents: .date
            )
            .datePickerStyle(.graphical)
            .padding()
            .navigationTitle("Change Date")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        dismiss()
                    }
                }

                ToolbarItem(placement: .confirmationAction) {
                    Button(action: save) {
                        Label("Save Date", systemImage: "checkmark")
                            .labelStyle(.iconOnly)
                    }
                    .tint(.accentColor)
                }
            }
            .alert("Date Couldn't Be Changed", isPresented: isShowingError) {
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
        let calendar = Calendar.autoupdatingCurrent
        let newDate = calendar.startOfDay(for: scheduledDate)

        do {
            if !calendar.isDate(todo.scheduledDate, inSameDayAs: newDate) {
                todo.order = try ItemOrdering.nextOrder(in: modelContext)
            }
            todo.scheduledDate = newDate
            try modelContext.save()
            dismiss()
        } catch {
            modelContext.rollback()
            errorMessage = error.localizedDescription
        }
    }
}
