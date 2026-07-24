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
    @State private var recurrenceTemplateBeingEdited: RecurrenceTemplate?
    @State private var isConfirmingDelete = false
    @State private var isConfirmingStop = false
    @State private var isDeleted = false

    init(item: Item) {
        self.item = item
        _title = State(initialValue: item.title)
        _notes = State(initialValue: item.notes ?? "")
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(alignment: .center, spacing: 12) {
                TextField("Title", text: $title, axis: .vertical)
                    .font(.title.weight(.semibold))
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .layoutPriority(1)
                    .accessibilityIdentifier("Item Title")

                if let event = item as? Event {
                    EventTimeLabel(
                        startDate: event.scheduledDate,
                        endDate: event.endDate
                    )
                    .accessibilityIdentifier("Event Time")
                }
            }

            ZStack(alignment: .topLeading) {
                if notes.isEmpty {
                    Text("Notes")
                        .foregroundStyle(.tertiary)
                        .padding(.vertical, 8)
                }

                TextEditor(text: $notes)
                    .scrollContentBackground(.hidden)
                    .padding(.horizontal, -5)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .padding()
        .navigationTitle("")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Menu {
                    if !(item is RecurrenceTemplate) {
                        Button(action: presentScheduleEditor) {
                            Label(scheduleActionTitle, systemImage: "calendar")
                        }
                    }

                    if item is RecurrenceTemplate {
                        Button(action: presentRecurrenceEditor) {
                            Label("Edit Repeat", systemImage: "repeat")
                        }

                        Divider()

                        Button(role: .destructive) {
                            isConfirmingStop = true
                        } label: {
                            Label("Stop Repeating", systemImage: "trash")
                        }
                    }

                    if !(item is RecurrenceTemplate) {
                        Button(role: .destructive) {
                            isConfirmingDelete = true
                        } label: {
                            Label("Delete", systemImage: "trash")
                        }
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
        .sheet(item: $recurrenceTemplateBeingEdited) { template in
            RecurrenceEditor(template: template)
                .presentationDetents([.medium, .large])
        }
        .confirmationDialog(
            "Delete this item?",
            isPresented: $isConfirmingDelete,
            titleVisibility: .visible
        ) {
            Button("Delete", role: .destructive, action: delete)
            Button("Cancel", role: .cancel) {}
        } message: {
            Text(deleteConfirmationMessage)
        }
        .confirmationDialog(
            "Stop repeating?",
            isPresented: $isConfirmingStop,
            titleVisibility: .visible
        ) {
            Button("Stop Repeating", role: .destructive, action: stopRepeating)
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("The current item and completed history will remain. Future virtual items will disappear.")
        }
        .alert("Nagare Couldn't Complete That Action", isPresented: isShowingError) {
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

    private var recurrenceTemplate: RecurrenceTemplate? {
        if let template = item as? RecurrenceTemplate {
            return template
        }
        if let todo = item as? Todo {
            return todo.recurrenceTemplate
        }
        if let event = item as? Event {
            return event.recurrenceTemplate
        }
        return nil
    }

    private var deleteConfirmationMessage: String {
        if recurrenceTemplate != nil {
            return "The current occurrence will be removed and the next occurrence will be generated."
        }
        return "This action cannot be undone."
    }

    private func presentScheduleEditor() {
        guard prepareItemForAction() else {
            return
        }
        if let todo = item as? Todo {
            todoBeingRescheduled = todo
        } else if let event = item as? Event {
            eventBeingRescheduled = event
        } else {
            errorMessage = "Nagare couldn't identify this item's schedule editor. (ITEM-001)"
        }
    }

    private func presentRecurrenceEditor() {
        guard prepareItemForAction() else {
            return
        }
        guard let template = item as? RecurrenceTemplate else {
            errorMessage = "Recurrence can only be edited from its template. (RECURRENCE-UI-004)"
            return
        }
        recurrenceTemplateBeingEdited = template
    }

    private func stopRepeating() {
        pendingSave?.cancel()
        guard let template = item as? RecurrenceTemplate else {
            errorMessage = "Recurrence can only be stopped from its template. (RECURRENCE-UI-005)"
            return
        }

        do {
            try RecurrencePersistence.deleteTemplate(
                template,
                in: modelContext
            )
            isDeleted = true
            dismiss()
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func delete() {
        pendingSave?.cancel()

        do {
            if let todo = item as? Todo {
                try RecurrencePersistence.delete(
                    todo,
                    in: modelContext
                )
            } else if let event = item as? Event {
                try RecurrencePersistence.delete(
                    event,
                    in: modelContext
                )
            } else {
                errorMessage = "Nagare couldn't identify the item to delete. (ITEM-002)"
                return
            }

            isDeleted = true
            dismiss()
        } catch {
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

            _ = save()
        }
    }

    private func prepareItemForAction() -> Bool {
        let trimmedTitle = title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedTitle.isEmpty else {
            errorMessage = "Give this item a title before continuing. (ITEM-003)"
            return false
        }
        return save()
    }

    @discardableResult
    private func save() -> Bool {
        let trimmedTitle = title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedTitle.isEmpty else {
            return false
        }

        let savedNotes = notes.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            ? nil
            : notes

        guard item.title != trimmedTitle || item.notes != savedNotes else {
            return true
        }

        item.title = trimmedTitle
        item.notes = savedNotes

        do {
            try modelContext.save()
            return true
        } catch {
            modelContext.rollback()
            errorMessage = error.localizedDescription
            return false
        }
    }
}
