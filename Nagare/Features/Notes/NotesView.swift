import SwiftUI

struct NotesView: View {
    @NagareDataStoreEnvironment private var dataStore

    let destination: NotesDestination

    @State private var draft = TextEditorDraft()
    @State private var itemScheduleBeingEdited: TodoRecordSnapshot?
    @State private var recurrenceTemplateBeingEdited:
        RecurrenceTemplateRecordSnapshot?
    @State private var errorMessage: String?
    @FocusState private var focusedField: NagareEditorField?

    private var record: NoteRecordSnapshot? {
        dataStore.snapshot.note(for: destination.recordID)
    }

    var body: some View {
        Group {
            if let record {
                editor(record)
            } else {
                ContentUnavailableView(
                    "Item Not Found",
                    systemImage: "questionmark.document"
                )
            }
        }
        .onChange(of: record, initial: true) { _, record in
            if let record { draft.receive(title: record.title, notes: record.notes) }
        }
        .nagareAutosave(draft, save: save)
        .nagareModal(item: $itemScheduleBeingEdited) { todo in
            TodoScheduleEditor(todo: todo)
        }
        .nagareModal(item: $recurrenceTemplateBeingEdited) { template in
            RecurrenceEditor(template: template)
                .nagareSheetDetents([.medium])
                .presentationDragIndicator(.visible)
        }
        .alert("Nagare Couldn't Complete That Action", isPresented: isShowingError) {
            Button("OK", role: .cancel) { errorMessage = nil }
        } message: {
            Text(errorMessage ?? "An unknown error occurred.")
        }
    }

    private func editor(_ record: NoteRecordSnapshot) -> some View {
        NavigationStack {
            editorContent(record)
                .nagareEditorMetadataChrome(
                    scheduleTitle: scheduleTitle,
                    scheduleAccessibilityIdentifier: "Notes Date",
                    projects: dataStore.projects,
                    selectedProject: selectedProject(for: record),
                    hasRepeat: hasRepeat(record),
                    projectAccessibilityIdentifier: "Notes Project",
                    repeatAccessibilityIdentifier: "Notes Repeat",
                    onSchedule: scheduleAction,
                    onSelectProject: { assign($0, to: record) },
                    onRepeat: repeatAction
                )
        }
    }

    private func editorContent(_ record: NoteRecordSnapshot) -> some View {
        NagareDocumentComposerLayout(bottomPadding: 0) {
            NagareEditableTitle(placeholder: "Title", text: $draft.title)
                .font(.title.weight(.semibold))
                .textFieldStyle(.plain)
                .focused($focusedField, equals: .title)
                .accessibilityIdentifier("Item Title")
        } document: {
            NagareDocumentEditor(
                text: $draft.notes,
                accessibilityIdentifier: "Item Notes",
                focus: $focusedField,
                bottomScrollContentMargin:
                    NagareDocumentBottomFade.scrollContentMargin
            )
        }
        .nagareDocumentBottomFade()
        .nagareAvoidsInitialFocus()
    }

    private func hasRepeat(_ record: NoteRecordSnapshot) -> Bool {
        switch record {
        case .recurrenceTemplate:
            true
        case .todo(let todo):
            todo.recurrenceTemplateID != nil
        }
    }

    private var repeatAction: (() -> Void)? {
        guard let template = destination.recurrenceTemplate(in: dataStore.snapshot)
        else { return nil }
        return {
            focusedField = nil
            recurrenceTemplateBeingEdited = template
        }
    }

    private var scheduleAction: (() -> Void)? {
        guard let item = destination.editableScheduledItem(in: dataStore.snapshot)
        else { return nil }
        return { presentScheduleEditor(for: item) }
    }

    private var scheduleTitle: String {
        guard let schedule = destination.schedule(in: dataStore.snapshot)
        else { return "No date" }
        return ScheduleToolbarPresentation.title(
            scheduledDate: schedule.scheduledDate,
            includesTime: schedule.includesTime,
            endDate: schedule.endDate
        )
    }

    private func selectedProject(
        for record: NoteRecordSnapshot
    ) -> ProjectRecordSnapshot? {
        guard let projectID = record.projectID,
              let project = dataStore.snapshot.projectsByID[projectID] else {
            return nil
        }
        return project
    }

    private var isShowingError: Binding<Bool> {
        Binding(
            get: { errorMessage != nil },
            set: { if !$0 { errorMessage = nil } }
        )
    }

    private func presentScheduleEditor(for item: ItemRecordSnapshot) {
        focusedField = nil
        itemScheduleBeingEdited = item
    }

    private func assign(
        _ project: ProjectRecordSnapshot?,
        to record: NoteRecordSnapshot
    ) {
        do {
            switch record {
            case .todo(let todo):
                try dataStore.assign(.item(todo.id), to: project?.id)
            case .recurrenceTemplate(let template):
                try dataStore.assign(
                    .recurrenceTemplate(template.id),
                    to: project?.id
                )
            }
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func save() {
        let changes = draft.changes()
        guard record != nil, !changes.isEmpty else { return }
        do {
            try dataStore.updateNote(destination.recordID, changes: changes)
            draft.didSave(changes)
            if let record { draft.receive(title: record.title, notes: record.notes) }
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}
