import SwiftData
import SwiftUI

struct TodoFormView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext

    @State private var title = ""
    @State private var scheduledDate = Date.now
    @State private var errorMessage: String?

    private var trimmedTitle: String {
        title.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("What needs doing?", text: $title)
                        .submitLabel(.done)
                        .onSubmit(save)

                    DatePicker(
                        "Date",
                        selection: $scheduledDate,
                        in: Calendar.autoupdatingCurrent.startOfDay(for: .now)...,
                        displayedComponents: .date
                    )
                }
            }
            .navigationTitle("New Todo")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        dismiss()
                    }
                }

                ToolbarItem(placement: .confirmationAction) {
                    Button(action: save) {
                        Label("Add Todo", systemImage: "checkmark")
                    }
                        .labelStyle(.iconOnly)
                        .tint(.accentColor)
                        .disabled(trimmedTitle.isEmpty)
                }
            }
            .alert("Todo Couldn't Be Created", isPresented: isShowingError) {
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
        guard !trimmedTitle.isEmpty else {
            return
        }

        let todo = Todo(title: trimmedTitle, scheduledDate: scheduledDate)
        modelContext.insert(todo)

        do {
            try modelContext.save()
            dismiss()
        } catch {
            modelContext.rollback()
            errorMessage = error.localizedDescription
        }
    }
}
