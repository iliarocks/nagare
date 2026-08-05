import SwiftData
import SwiftUI

struct ProjectDetailView: View {
    @Environment(\.modelContext) private var modelContext

    @Query private var todos: [Todo]
    @Query private var events: [Event]
    @Query private var templates: [RecurrenceTemplate]

    let project: Project

    @State private var isCreatingItem = false
    @State private var title: String
    @State private var notes: String
    @State private var pendingSave: Task<Void, Never>?
    @State private var notesDestination: NotesDestination?
    @State private var notesDetent: PresentationDetent = .medium
    @State private var todoBeingRescheduled: Todo?
    @State private var eventBeingRescheduled: Event?
    @State private var recurrenceTemplateBeingEdited: RecurrenceTemplate?
    @State private var errorMessage: String?

    init(project: Project) {
        self.project = project
        _title = State(initialValue: project.title)
        _notes = State(initialValue: project.notes ?? "")
    }

    private var actualItems: [Item] {
        Item.orderedInProject(
            todos: todos.filter {
                $0.project?.id == project.id && $0.completedAt == nil
            },
            events: events.filter { $0.project?.id == project.id }
        )
    }

    private var repeatTemplates: [RecurrenceTemplate] {
        templates
            .filter { $0.project?.id == project.id }
            .sorted {
                let firstOrder = currentProjectOrder(for: $0)
                let secondOrder = currentProjectOrder(for: $1)
                if firstOrder != secondOrder {
                    return firstOrder < secondOrder
                }
                return $0.id.uuidString < $1.id.uuidString
            }
    }

    var body: some View {
        itemList
        .navigationTitle("")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button {
                    isCreatingItem = true
                } label: {
                    Label("New Item", systemImage: "plus")
                        .labelStyle(.iconOnly)
                }
            }
        }
        .sheet(isPresented: $isCreatingItem) {
            CreateView(project: project)
        }
        .sheet(item: $notesDestination, onDismiss: resetNotesSheet) {
            NotesSheet(destination: $0, detent: $notesDetent)
                .id($0.id)
        }
        .sheet(item: $todoBeingRescheduled) { todo in
            NavigationStack {
                TodoDateEditor(todo: todo)
            }
            .presentationDetents([.fraction(0.38)])
        }
        .sheet(item: $eventBeingRescheduled) { event in
            NavigationStack {
                EventScheduleEditor(event: event)
            }
            .presentationDetents([.medium])
        }
        .sheet(item: $recurrenceTemplateBeingEdited) { template in
            NavigationStack {
                RecurrenceEditor(template: template)
            }
        }
        .onChange(of: title) {
            scheduleProjectSave()
        }
        .onChange(of: notes) {
            scheduleProjectSave()
        }
        .onDisappear {
            pendingSave?.cancel()
            saveProject()
        }
        .alert("Nagare Couldn't Save", isPresented: isShowingError) {
            Button("OK", role: .cancel) {
                errorMessage = nil
            }
        } message: {
            Text(errorMessage ?? "An unknown error occurred.")
        }
    }

    private var itemList: some View {
        List {
            projectDetailsSection

            if actualItems.isEmpty && repeatTemplates.isEmpty {
                Section {
                    ContentUnavailableView(
                        "No Project Items",
                        systemImage: "folder"
                    )
                    .frame(maxWidth: .infinity, minHeight: 200)
                    .listRowInsets(EdgeInsets())
                    .listRowBackground(Color.clear)
                    .listRowSeparator(.hidden)
                }
            }

            if !actualItems.isEmpty {
                Section {
                    ForEach(actualItems) { item in
                        ItemRow(
                            item: item,
                            onOpen: open,
                            onComplete: complete,
                            onChangeSchedule: presentScheduleEditor,
                            onDelete: delete
                        )
                    }
                    .reorderable(collectionID: project.id)
                }
            }

            if !repeatTemplates.isEmpty {
                Section {
                    ForEach(repeatTemplates) { template in
                        ProjectRepeatRow(
                            template: template,
                            onOpen: { notesDestination = .template(template) },
                            onChangeRepeat: {
                                recurrenceTemplateBeingEdited = template
                            },
                            onDelete: { deleteTemplate(template) }
                        )
                    }
                }
            }
        }
        .listSectionSpacing(.custom(48))
        .reorderContainer(for: Item.self, in: UUID.self) {
            apply($0)
        }
    }

    private var projectDetailsSection: some View {
        Section {
            VStack(alignment: .leading, spacing: 12) {
                TextField("Project Title", text: $title, axis: .vertical)
                    .font(.title.weight(.semibold))
                    .submitLabel(.done)
                    .accessibilityIdentifier("Project Title")

                ZStack(alignment: .topLeading) {
                    if notes.isEmpty {
                        Text("Notes")
                            .foregroundStyle(.tertiary)
                            .padding(.vertical, 8)
                    }

                    TextEditor(text: $notes)
                        .scrollContentBackground(.hidden)
                        .padding(.horizontal, -5)
                        .accessibilityIdentifier("Project Notes")
                }
                .frame(minHeight: 88)
            }
            .padding(.vertical, 4)
        }
    }

    private func scheduleProjectSave() {
        pendingSave?.cancel()
        pendingSave = Task {
            do {
                try await Task.sleep(for: .milliseconds(500))
            } catch {
                return
            }

            saveProject()
        }
    }

    private func saveProject() {
        let trimmedTitle = title.trimmingCharacters(
            in: .whitespacesAndNewlines
        )
        guard !trimmedTitle.isEmpty else {
            return
        }

        let savedNotes = notes.trimmingCharacters(
            in: .whitespacesAndNewlines
        ).isEmpty ? nil : notes
        guard project.title != trimmedTitle || project.notes != savedNotes else {
            return
        }

        project.title = trimmedTitle
        project.notes = savedNotes

        do {
            try modelContext.save()
        } catch {
            modelContext.rollback()
            errorMessage = error.localizedDescription
        }
    }

    private func apply(_ difference: ReorderDifference<ItemID, UUID>) {
        guard difference.destination.collectionID == project.id else {
            return
        }
        let destinationID: ItemID?
        switch difference.destination.position {
        case .before(let id):
            destinationID = id
        case .end:
            destinationID = nil
        }

        do {
            try ProjectItemOrdering.move(
                difference.sources,
                before: destinationID,
                in: project,
                context: modelContext
            )
        } catch {
            modelContext.rollback()
            errorMessage = error.localizedDescription
        }
    }

    private func open(_ item: Item) {
        notesDetent = .medium
        notesDestination = NotesDestination(item)
    }

    private func complete(_ todo: Todo) {
        do {
            try withAnimation {
                _ = try RecurrencePersistence.complete(todo, in: modelContext)
            }
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func delete(_ item: Item) {
        do {
            switch item {
            case .todo(let todo):
                try RecurrencePersistence.delete(todo, in: modelContext)
            case .event(let event):
                try RecurrencePersistence.delete(event, in: modelContext)
            }
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func deleteTemplate(_ template: RecurrenceTemplate) {
        do {
            try RecurrencePersistence.deleteTemplate(template, in: modelContext)
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func presentScheduleEditor(_ item: Item) {
        switch item {
        case .todo(let todo):
            todoBeingRescheduled = todo
        case .event(let event):
            eventBeingRescheduled = event
        }
    }

    private func currentProjectOrder(
        for template: RecurrenceTemplate
    ) -> String {
        switch template.itemType {
        case .todo:
            template.todoOccurrences.first {
                $0.id == template.currentItemID && $0.completedAt == nil
            }?.projectOrder ?? ""
        case .event:
            template.eventOccurrences.first {
                $0.id == template.currentItemID
            }?.projectOrder ?? ""
        case nil:
            ""
        }
    }

    private func resetNotesSheet() {
        notesDetent = .medium
    }

    private var isShowingError: Binding<Bool> {
        Binding(
            get: { errorMessage != nil },
            set: { if !$0 { errorMessage = nil } }
        )
    }
}
