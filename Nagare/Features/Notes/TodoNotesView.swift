import SwiftData
import SwiftUI

struct TodoNotesView: View {
    @Environment(\.modelContext) private var modelContext

    let todo: Todo

    @State private var title: String
    @State private var notes: String
    @State private var pendingSave: Task<Void, Never>?
    @State private var errorMessage: String?

    init(todo: Todo) {
        self.todo = todo
        _title = State(initialValue: todo.title)
        _notes = State(initialValue: todo.notes ?? "")
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            TextField("Title", text: $title, axis: .vertical)
                .font(.title2.weight(.semibold))

            Divider()

            ZStack(alignment: .topLeading) {
                if notes.isEmpty {
                    Text("Notes")
                        .foregroundStyle(.tertiary)
                        .padding(.horizontal, 5)
                        .padding(.vertical, 8)
                }

                TextEditor(text: $notes)
                    .scrollContentBackground(.hidden)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .padding()
        .navigationTitle("")
        .navigationBarTitleDisplayMode(.inline)
        .onChange(of: title) {
            scheduleSave()
        }
        .onChange(of: notes) {
            scheduleSave()
        }
        .onDisappear {
            pendingSave?.cancel()
            save()
        }
        .alert("Todo Couldn't Be Saved", isPresented: isShowingError) {
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

    private func scheduleSave() {
        pendingSave?.cancel()
        pendingSave = Task {
            do {
                try await Task.sleep(for: .milliseconds(500))
            } catch {
                return
            }

            save()
        }
    }

    private func save() {
        let trimmedTitle = title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedTitle.isEmpty else {
            return
        }

        let savedNotes = notes.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            ? nil
            : notes

        guard todo.title != trimmedTitle || todo.notes != savedNotes else {
            return
        }

        todo.title = trimmedTitle
        todo.notes = savedNotes

        do {
            try modelContext.save()
        } catch {
            modelContext.rollback()
            errorMessage = error.localizedDescription
        }
    }
}
