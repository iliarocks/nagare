import SwiftData
import SwiftUI

struct NotesView<Item: Note>: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext

    let item: Item

    @State private var title: String
    @State private var notes: String
    @State private var pendingSave: Task<Void, Never>?
    @State private var errorMessage: String?
    @State private var todoBeingRescheduled: Todo?
    @State private var eventBeingRescheduled: Event?
    @State private var isConfirmingDelete = false
    @State private var isDeleted = false

    init(item: Item) {
        self.item = item
        _title = State(initialValue: item.title)
        _notes = State(initialValue: item.notes ?? "")
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
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Menu {
                    Button(action: presentScheduleEditor) {
                        Label(scheduleActionTitle, systemImage: "calendar")
                    }

                    Divider()

                    Button(role: .destructive) {
                        isConfirmingDelete = true
                    } label: {
                        Label("Delete", systemImage: "trash")
                    }
                } label: {
                    Label("Item Actions", systemImage: "ellipsis")
                        .labelStyle(.iconOnly)
                }
            }
        }
        .onChange(of: title) {
            scheduleSave()
        }
        .onChange(of: notes) {
            scheduleSave()
        }
        .onDisappear {
            pendingSave?.cancel()
            if !isDeleted {
                save()
            }
        }
        .sheet(item: $todoBeingRescheduled) { todo in
            TodoDateEditor(todo: todo)
                .presentationDetents([.medium])
        }
        .sheet(item: $eventBeingRescheduled) { event in
            EventScheduleEditor(event: event)
                .presentationDetents([.medium])
        }
        .confirmationDialog(
            "Delete this item?",
            isPresented: $isConfirmingDelete,
            titleVisibility: .visible
        ) {
            Button("Delete", role: .destructive, action: delete)
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("This action cannot be undone.")
        }
        .alert("Item Couldn't Be Saved", isPresented: isShowingError) {
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

    private var scheduleActionTitle: String {
        item is Event ? "Change Schedule" : "Change Date"
    }

    private func presentScheduleEditor() {
        if let todo = item as? Todo {
            todoBeingRescheduled = todo
        } else if let event = item as? Event {
            eventBeingRescheduled = event
        } else {
            errorMessage = "Nagare couldn't identify this item's schedule editor. (ITEM-001)"
        }
    }

    private func delete() {
        pendingSave?.cancel()

        if let todo = item as? Todo {
            modelContext.delete(todo)
        } else if let event = item as? Event {
            modelContext.delete(event)
        } else {
            errorMessage = "Nagare couldn't identify the item to delete. (ITEM-002)"
            return
        }

        do {
            try modelContext.save()
            isDeleted = true
            dismiss()
        } catch {
            modelContext.rollback()
            errorMessage = error.localizedDescription
        }
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

        guard item.title != trimmedTitle || item.notes != savedNotes else {
            return
        }

        item.title = trimmedTitle
        item.notes = savedNotes

        do {
            try modelContext.save()
        } catch {
            modelContext.rollback()
            errorMessage = error.localizedDescription
        }
    }
}
