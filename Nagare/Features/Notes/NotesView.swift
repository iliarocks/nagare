import SwiftUI

struct NotesView: View {
    @NagareDataStoreEnvironment private var dataStore

    let id: NoteRecordID
    let onOpenUpcomingDate: (Date) -> Void

    @State private var title = ""
    @State private var notes = ""
    @State private var lastLoadedRecord: NoteRecordSnapshot?
    @State private var itemScheduleBeingEdited: TodoRecordSnapshot?
    @State private var recurrenceTemplateBeingEdited:
        RecurrenceTemplateRecordSnapshot?
    @State private var pendingSave: Task<Void, Never>?
    @State private var errorMessage: String?
    @FocusState private var focusedField: NagareEditorField?

    init(
        id: NoteRecordID,
        onOpenUpcomingDate: @escaping (Date) -> Void = { _ in }
    ) {
        self.id = id
        self.onOpenUpcomingDate = onOpenUpcomingDate
    }

    private var record: NoteRecordSnapshot? {
        dataStore.snapshot.note(for: id)
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
        .task { load(record) }
        .onChange(of: record) { _, record in
            load(record)
        }
        .onDisappear {
            pendingSave?.cancel()
            save()
        }
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
                    scheduleTitle: scheduleTitle(for: record),
                    scheduleAccessibilityIdentifier: "Notes Date",
                    projects: dataStore.projects,
                    selectedProject: selectedProject(for: record),
                    hasRepeat: hasRepeat(record),
                    projectAccessibilityIdentifier: "Notes Project",
                    repeatAccessibilityIdentifier: "Notes Repeat",
                    onSchedule: scheduleAction(for: record),
                    onSelectProject: { assign($0, to: record) },
                    onRepeat: repeatAction(for: record)
                )
        }
    }

    private func editorContent(_ record: NoteRecordSnapshot) -> some View {
        NagareDocumentComposerLayout(bottomPadding: 0) {
            NagareEditableTitle(placeholder: "Title", text: $title)
                .font(.title.weight(.semibold))
                .textFieldStyle(.plain)
                .focused($focusedField, equals: .title)
                .accessibilityIdentifier("Item Title")
        } document: {
            NagareDocumentEditor(
                text: $notes,
                accessibilityIdentifier: "Item Notes",
                focus: $focusedField,
                bottomScrollContentMargin:
                    NagareDocumentBottomFade.scrollContentMargin
            )
        }
        .nagareDocumentBottomFade()
        .nagareAvoidsInitialFocus()
        .onChange(of: title) { scheduleSave() }
        .onChange(of: notes) { scheduleSave() }
    }

    private func hasRepeat(_ record: NoteRecordSnapshot) -> Bool {
        switch record {
        case .recurrenceTemplate:
            true
        case .todo(let todo):
            todo.recurrenceTemplateID != nil
        }
    }

    private func repeatAction(
        for record: NoteRecordSnapshot
    ) -> (() -> Void)? {
        switch record {
        case .recurrenceTemplate(let template):
            return {
                focusedField = nil
                recurrenceTemplateBeingEdited = template
            }
        case .todo(let todo):
            guard let templateID = todo.recurrenceTemplateID else {
                return nil
            }

            guard let template = dataStore.snapshot.templatesByID[templateID]
            else {
                return nil
            }

            guard let nextDate = RecurrencePresentation.nextDate(
                after: todo.scheduledDate,
                for: template
            ) else { return nil }

            return {
                focusedField = nil
                onOpenUpcomingDate(nextDate)
            }
        }
    }

    private func scheduleAction(
        for record: NoteRecordSnapshot
    ) -> (() -> Void)? {
        guard let item = scheduledItem(for: record) else { return nil }
        return { presentScheduleEditor(for: item) }
    }

    private func scheduleTitle(for record: NoteRecordSnapshot) -> String {
        guard let item = scheduledItem(for: record) else { return "No date" }
        return ScheduleToolbarPresentation.title(
            scheduledDate: item.scheduledDate,
            includesTime: item.includesTime,
            endDate: item.endDate
        )
    }

    private func scheduledItem(
        for record: NoteRecordSnapshot
    ) -> ItemRecordSnapshot? {
        switch record {
        case .todo(let todo): todo
        case .recurrenceTemplate(let template):
            dataStore.snapshot.currentItem(for: template)
        }
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

    private func load(_ record: NoteRecordSnapshot?) {
        guard let record, record != lastLoadedRecord else { return }
        let hasUnsavedChanges = lastLoadedRecord.map {
            title != $0.title || normalizedNotes != $0.notes
        } ?? false
        guard !hasUnsavedChanges else { return }
        title = record.title
        notes = record.notes ?? ""
        lastLoadedRecord = record
    }

    private var normalizedNotes: String? {
        notes.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            ? nil
            : notes
    }

    private func scheduleSave() {
        pendingSave?.cancel()
        pendingSave = Task {
            do { try await Task.sleep(for: .milliseconds(500)) }
            catch { return }
            save()
        }
    }

    private func save() {
        let trimmedTitle = title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let record,
              record.title != trimmedTitle || record.notes != normalizedNotes else {
            return
        }

        do {
            try dataStore.updateNote(
                id,
                title: trimmedTitle,
                notes: normalizedNotes
            )
            lastLoadedRecord = nil
            load(dataStore.snapshot.note(for: id))
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}
