import SwiftUI

struct ProjectDetailView: View {
    @NagareDataStoreEnvironment private var dataStore

    let project: ProjectRecordSnapshot

    @State private var isCreatingItem = false
    @State private var draft: TextEditorDraft
    @State private var notesDestination: NotesDestination?
    @State private var notesDetent: PresentationDetent = .medium
    @State private var todoBeingRescheduled: TodoRecordSnapshot?
    @State private var recurrenceTemplateBeingEdited: RecurrenceTemplateRecordSnapshot?
    @State private var itemSelectionBeingRescheduled: ItemSelectionAction?
    @State private var selectedItemIDs: Set<ItemID> = []
    @State private var errorMessage: String?

    private var todos: [TodoRecordSnapshot] {
        dataStore.todos
    }

    private var templates: [RecurrenceTemplateRecordSnapshot] {
        dataStore.recurrenceTemplates
    }

    private var currentProject: ProjectRecordSnapshot {
        dataStore.snapshot.projectsByID[project.id] ?? project
    }

    init(project: ProjectRecordSnapshot) {
        self.project = project
        _draft = State(initialValue: TextEditorDraft(title: project.title, notes: project.notes))
    }

    private var actualItems: [ItemRecordSnapshot] {
        TodoRecordSnapshot.orderedInProject(
            todos.filter {
                $0.projectID == project.id && $0.completedAt == nil
            }
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
                .nagareToolbarButton()
            }
        }
        .nagareDraftComposer(
            isPresented: $isCreatingItem
        ) {
            CreateView(project: currentProject, onDismiss: {
                isCreatingItem = false
            })
        }
        .nagareModal(item: $notesDestination, onDismiss: resetNotesSheet) {
            NotesSheet(
                destination: $0,
                detent: $notesDetent
            )
                .id($0.id)
        }
        .nagareModal(item: $todoBeingRescheduled) { todo in
            TodoScheduleEditor(todo: todo)
        }
        .nagareModal(item: $itemSelectionBeingRescheduled) { selection in
            ItemDateEditor(items: selection.items)
                .nagareSheetDetents([.medium])
                .presentationDragIndicator(.visible)
        }
        .nagareModal(item: $recurrenceTemplateBeingEdited) { template in
            RecurrenceEditor(template: template)
                .nagareSheetDetents([.medium])
                .presentationDragIndicator(.visible)
        }
        .nagareAutosave(draft, save: saveProject)
        .onChange(of: currentProject, initial: true) { _, project in
            draft.receive(title: project.title, notes: project.notes)
        }
        .onChange(of: Set(actualItems.map(\.id))) { _, availableIDs in
#if os(macOS)
            selectedItemIDs.formIntersection(availableIDs)
#endif
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
        selectableItemList
        .nagareListSectionSpacing(.custom(48))
        .reorderContainer(for: ItemRecordSnapshot.self, in: UUID.self) {
            apply($0)
        }
    }

    @ViewBuilder
    private var selectableItemList: some View {
        List {
            itemListRows
        }
    }

    @ViewBuilder
    private var itemListRows: some View {
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
                        onToggleSelection: {
                            toggleSelection(of: item.id)
                        },
                        onComplete: complete,
                        contextItems: contextItems(for: item),
                        onChangeSchedule: presentScheduleEditor,
                        onDelete: delete
                    )
                    .nagareCommandSelection(
                        position: selectionPosition(for: item.id),
                        toggle: { toggleSelection(of: item.id) }
                    )
                }
                .reorderable(collectionID: project.id)
                .nagareDesktopItemListRows()
            } header: {
                Text("Items")
                    .nagareContentSectionHeader()
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
                        onDelete: { deleteTemplate(template) }
                    )
                }
                .nagareDesktopItemListRows()
            } header: {
                Text("Repeating")
                    .nagareContentSectionHeader()
            }
        }
    }

    private var projectDetailsSection: some View {
        Section {
            VStack(alignment: .leading, spacing: 12) {
                NagareEditableTitle(
                    placeholder: "Project Title",
                    text: $draft.title
                )
                    .font(.title.weight(.semibold))
                    .textFieldStyle(.plain)
                    .submitLabel(.done)
                    .accessibilityIdentifier("Project Title")

                NagareDocumentEditor(
                    text: $draft.notes,
                    accessibilityIdentifier: "Project Notes"
                )
                .frame(minHeight: 88)
            }
            .padding(.vertical, 4)
            .nagareDesktopListRow()
        }
    }

    private func selectionPosition(
        for id: ItemID
    ) -> NagareSelectionPosition {
        NagareSelectionPosition.resolve(
            id: id,
            orderedIDs: actualItems.map(\.id),
            selectedIDs: selectedItemIDs
        )
    }

    private func saveProject() {
        // An empty title remains a local draft; it must not block notes saves.
        let changes = draft.changes(allowsEmptyTitle: false)
        guard !changes.isEmpty else { return }
        do {
            try dataStore.updateProject(project.id, changes: changes)
            draft.didSave(changes)
            draft.receive(title: currentProject.title, notes: currentProject.notes)
        } catch {
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

    private func delete(_ items: [ItemRecordSnapshot]) {
        do {
            try dataStore.deleteItems(items.map(\.id))
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

    private func contextItems(
        for item: ItemRecordSnapshot
    ) -> [ItemRecordSnapshot] {
#if os(macOS)
        guard selectedItemIDs.count > 1,
              selectedItemIDs.contains(item.id) else {
            return [item]
        }
        return actualItems.filter { selectedItemIDs.contains($0.id) }
#else
        return [item]
#endif
    }

    private func toggleSelection(of id: ItemID) {
        if selectedItemIDs.contains(id) {
            selectedItemIDs.remove(id)
        } else {
            selectedItemIDs.insert(id)
        }
    }

    private func presentScheduleEditor(_ items: [ItemRecordSnapshot]) {
        guard items.count == 1, let item = items.first else {
            itemSelectionBeingRescheduled = ItemSelectionAction(items: items)
            return
        }
        todoBeingRescheduled = item
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
