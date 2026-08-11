import SwiftData
import SwiftUI

struct NotesView<Record: Note>: View {
    @Environment(\.modelContext) private var modelContext

    let item: Record
    let onOpenProject: (Project) -> Void

    @State private var title: String
    @State private var notes: String
    @State private var todoBeingRescheduled: Todo?
    @State private var eventBeingRescheduled: Event?
    @State private var pendingSave: Task<Void, Never>?
    @State private var errorMessage: String?

    init(
        item: Record,
        onOpenProject: @escaping (Project) -> Void = { _ in }
    ) {
        self.item = item
        self.onOpenProject = onOpenProject
        _title = State(initialValue: item.title)
        _notes = State(initialValue: item.notes ?? "")
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            metadata

            HStack(alignment: .center, spacing: 12) {
                TextField("Title", text: $title, axis: .vertical)
                    .font(.title.weight(.semibold))
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .layoutPriority(1)
                    .accessibilityIdentifier("Item Title")

                if let project = associatedProject {
                    Button {
                        onOpenProject(project)
                    } label: {
                        Text(project.title)
                            .lineLimit(1)
                            .frame(minWidth: 44, alignment: .trailing)
                    }
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .buttonStyle(.plain)
                    .frame(maxWidth: 140, alignment: .trailing)
                    .layoutPriority(2)
                    .accessibilityIdentifier("Notes Project")
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
                    .accessibilityIdentifier("Item Notes")
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .padding(24)
        .padding(.top, 8)
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
        .sheet(item: $todoBeingRescheduled) { todo in
            TodoDateEditor(todo: todo)
                .presentationDetents([.medium])
                .presentationDragIndicator(.visible)
        }
        .sheet(item: $eventBeingRescheduled) { event in
            EventScheduleEditor(event: event)
                .presentationDetents([EventScheduleEditor.sheetDetent])
                .presentationDragIndicator(.visible)
        }
        .alert("Nagare Couldn't Complete That Action", isPresented: isShowingError) {
            Button("OK", role: .cancel) {
                errorMessage = nil
            }
        } message: {
            Text(errorMessage ?? "An unknown error occurred.")
        }
    }

    @ViewBuilder
    private var metadata: some View {
        if let scheduledItem {
            HStack(spacing: 12) {
                Button {
                    presentScheduleEditor(for: scheduledItem)
                } label: {
                    Text(
                        scheduledItem.scheduledDate,
                        format: .dateTime
                            .weekday(.abbreviated)
                            .month(.abbreviated)
                            .day()
                    )
                }
                .accessibilityIdentifier("Notes Date")

                Spacer(minLength: 16)

                if let scheduledEvent {
                    EventTimeLabel(
                        startDate: scheduledEvent.scheduledDate,
                        endDate: scheduledEvent.endDate
                    )
                    .accessibilityIdentifier("Event Time")
                }
            }
            .font(.subheadline)
            .foregroundStyle(.secondary)
            .buttonStyle(.plain)
        }
    }

    private var scheduledEvent: Event? {
        guard case .event(let event) = scheduledItem else {
            return nil
        }
        return event
    }

    private var scheduledItem: Item? {
        if let todo = item as? Todo {
            return .todo(todo)
        }
        if let event = item as? Event {
            return .event(event)
        }
        guard let template = item as? RecurrenceTemplate else {
            return nil
        }
        switch template.itemType {
        case .todo:
            return template.todoOccurrences.first(where: {
                $0.id == template.currentItemID && $0.completedAt == nil
            }).map(Item.todo)
        case .event:
            return template.eventOccurrences.first(where: {
                $0.id == template.currentItemID
            }).map(Item.event)
        case nil:
            return nil
        }
    }

    private var associatedProject: Project? {
        if let todo = item as? Todo {
            return todo.project
        }
        if let event = item as? Event {
            return event.project
        }
        return (item as? RecurrenceTemplate)?.project
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

    private func presentScheduleEditor(for item: Item) {
        switch item {
        case .todo(let todo):
            todoBeingRescheduled = todo
        case .event(let event):
            eventBeingRescheduled = event
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

    @discardableResult
    private func save() -> Bool {
        let trimmedTitle = title.trimmingCharacters(in: .whitespacesAndNewlines)
        let savedNotes = notes.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            ? nil
            : notes

        guard item.title != trimmedTitle || item.notes != savedNotes else {
            return true
        }

        item.title = trimmedTitle
        item.notes = savedNotes

        do {
            try SwiftDataTransaction.save(modelContext)
            return true
        } catch {
            modelContext.rollback()
            errorMessage = error.localizedDescription
            return false
        }
    }
}
