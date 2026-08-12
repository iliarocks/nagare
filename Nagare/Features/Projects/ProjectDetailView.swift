import SwiftUI

struct ProjectDetailView: View {
    @NagareDataStoreEnvironment private var dataStore

    let project: ProjectRecordSnapshot

    @State private var isCreatingItem = false
    @State private var title: String
    @State private var notes: String
    @State private var lastLoadedProject: ProjectRecordSnapshot?
    @State private var pendingSave: Task<Void, Never>?
    @State private var notesDestination: NotesDestination?
    @State private var notesDetent: PresentationDetent = .medium
    @State private var todoBeingRescheduled: TodoRecordSnapshot?
    @State private var eventBeingRescheduled: EventRecordSnapshot?
    @State private var recurrenceTemplateBeingEdited: RecurrenceTemplateRecordSnapshot?
    @State private var projectMoveTarget: ProjectMoveTarget?
    @State private var errorMessage: String?

    private var todos: [TodoRecordSnapshot] {
        dataStore.todos
    }

    private var events: [EventRecordSnapshot] {
        dataStore.events
    }

    private var templates: [RecurrenceTemplateRecordSnapshot] {
        dataStore.recurrenceTemplates
    }

    private var currentProject: ProjectRecordSnapshot {
        dataStore.snapshot.projectsByID[project.id] ?? project
    }

    init(project: ProjectRecordSnapshot) {
        self.project = project
        _title = State(initialValue: project.title)
        _notes = State(initialValue: project.notes ?? "")
        _lastLoadedProject = State(initialValue: project)
    }

    private var actualItems: [ItemRecordSnapshot] {
        ItemRecordSnapshot.orderedInProject(
            todos: todos.filter {
                $0.projectID == project.id && $0.completedAt == nil
            },
            events: events.filter { $0.projectID == project.id }
        )
    }

    private var repeatTemplates: [RecurrenceTemplateRecordSnapshot] {
        templates
            .filter { $0.projectID == project.id }
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
        .nagareProjectNavigationTitle(currentProject.title)
        .nagareInlineNavigationTitle()
        .toolbar {
#if os(macOS)
            ToolbarSpacer(.flexible)
#endif

            ToolbarItem(placement: .nagareTrailing) {
                Button {
                    isCreatingItem = true
                } label: {
                    Label("New Item", systemImage: "plus")
                        .labelStyle(.iconOnly)
                }
            }
        }
        .nagareDraftComposer(
            isPresented: $isCreatingItem
        ) {
            CreateView(project: currentProject) {
                isCreatingItem = false
            }
        }
        .sheet(item: $notesDestination, onDismiss: resetNotesSheet) {
            NotesSheet(
                destination: $0,
                detent: $notesDetent,
                onOpenProject: { _ in notesDestination = nil }
            )
                .id($0.id)
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
        .sheet(item: $recurrenceTemplateBeingEdited) { template in
            RecurrenceEditor(template: template)
                .presentationDetents([.medium])
                .presentationDragIndicator(.visible)
        }
        .sheet(item: $projectMoveTarget) { target in
            ProjectMoveEditor(target: target)
                .presentationDetents([.fraction(0.25)])
                .presentationDragIndicator(.visible)
        }
        .onChange(of: title) {
            scheduleProjectSave()
        }
        .onChange(of: notes) {
            scheduleProjectSave()
        }
        .onChange(of: currentProject, initial: true) { _, project in
            load(project)
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
                            onMoveProject: {
                                projectMoveTarget = ProjectMoveTarget($0)
                            },
                            onDelete: delete
                        )
                    }
                    .reorderable(collectionID: project.id)
                    .nagareDesktopListRow()
                }
            }

            if !repeatTemplates.isEmpty {
                Section {
                    ForEach(repeatTemplates) { template in
                        ProjectRepeatRow(
                            template: template,
                            onOpen: { notesDestination = .template(template.id) },
                            onChangeRepeat: {
                                recurrenceTemplateBeingEdited = template
                            },
                            onMoveProject: {
                                projectMoveTarget = .template(template)
                            },
                            onDelete: { deleteTemplate(template) }
                        )
                    }
                    .nagareDesktopListRow()
                }
            }
        }
        .nagareListSectionSpacing(.custom(48))
        .reorderContainer(for: ItemRecordSnapshot.self, in: UUID.self) {
            apply($0)
        }
    }

    private var projectDetailsSection: some View {
        Section {
            VStack(alignment: .leading, spacing: 12) {
                NagareEditableTitle(
                    placeholder: "Project Title",
                    text: $title
                )
                    .font(.title.weight(.semibold))
                    .textFieldStyle(.plain)
                    .submitLabel(.done)
                    .accessibilityIdentifier("Project Title")

                ZStack(alignment: .topLeading) {
                    TextEditor(text: $notes)
                        .nagareDocumentEditorStyle()
                        .accessibilityIdentifier("Project Notes")

                    if notes.isEmpty {
                        Text("Notes")
                            .nagareDocumentPlaceholderStyle()
                    }
                }
                .frame(minHeight: 88)
            }
            .padding(.vertical, 4)
            .nagareDesktopListRow()
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
        guard currentProject.title != trimmedTitle
                || currentProject.notes != savedNotes else {
            return
        }

        do {
            try dataStore.updateProject(
                project.id,
                title: trimmedTitle,
                notes: savedNotes
            )
            lastLoadedProject = nil
            load(currentProject)
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func load(_ project: ProjectRecordSnapshot) {
        guard project != lastLoadedProject else { return }
        let hasUnsavedChanges = lastLoadedProject.map {
            title != $0.title || normalizedNotes != $0.notes
        } ?? false
        guard !hasUnsavedChanges else { return }
        title = project.title
        notes = project.notes ?? ""
        lastLoadedProject = project
    }

    private var normalizedNotes: String? {
        notes.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            ? nil
            : notes
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
            try dataStore.moveProjectItems(
                difference.sources,
                before: destinationID,
                projectID: project.id
            )
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func open(_ item: ItemRecordSnapshot) {
        notesDetent = .medium
        notesDestination = NotesDestination(item)
    }

    private func complete(_ todo: TodoRecordSnapshot) {
        do {
            try withAnimation {
                try dataStore.completeTodo(todo.id)
            }
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func delete(_ item: ItemRecordSnapshot) {
        do {
            switch item {
            case .todo(let todo):
                try dataStore.deleteItem(.todo(todo.id))
            case .event(let event):
                try dataStore.deleteItem(.event(event.id))
            }
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func deleteTemplate(_ template: RecurrenceTemplateRecordSnapshot) {
        do {
            try dataStore.deleteRecurrenceTemplate(template.id)
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func presentScheduleEditor(_ item: ItemRecordSnapshot) {
        switch item {
        case .todo(let todo):
            todoBeingRescheduled = todo
        case .event(let event):
            eventBeingRescheduled = event
        }
    }

    private func currentProjectOrder(
        for template: RecurrenceTemplateRecordSnapshot
    ) -> String {
        dataStore.snapshot.currentProjectOrder(for: template)
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
