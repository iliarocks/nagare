import SwiftUI

struct NotesView: View {
    @NagareDataStoreEnvironment private var dataStore

    let id: NoteRecordID
    let onOpenProject: (UUID) -> Void

    @State private var title = ""
    @State private var notes = ""
    @State private var lastLoadedRecord: NoteRecordSnapshot?
    @State private var todoBeingRescheduled: TodoRecordSnapshot?
    @State private var eventBeingRescheduled: EventRecordSnapshot?
    @State private var pendingSave: Task<Void, Never>?
    @State private var errorMessage: String?

    init(
        id: NoteRecordID,
        onOpenProject: @escaping (UUID) -> Void = { _ in }
    ) {
        self.id = id
        self.onOpenProject = onOpenProject
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
            Button("OK", role: .cancel) { errorMessage = nil }
        } message: {
            Text(errorMessage ?? "An unknown error occurred.")
        }
    }

    private func editor(_ record: NoteRecordSnapshot) -> some View {
        VStack(alignment: .leading, spacing: 16) {
            metadata(record)

            HStack(alignment: .center, spacing: 12) {
                TextField("Title", text: $title, axis: .vertical)
                    .font(.title.weight(.semibold))
                    .textFieldStyle(.plain)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .layoutPriority(1)
                    .accessibilityIdentifier("Item Title")

                if let projectID = record.projectID,
                   let project = dataStore.snapshot.projectsByID[projectID] {
                    Button { onOpenProject(projectID) } label: {
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
                TextEditor(text: $notes)
                    .scrollContentBackground(.hidden)
                    .padding(.horizontal, -5)
                    .accessibilityIdentifier("Item Notes")

                if notes.isEmpty {
                    Text("Notes")
                        .foregroundStyle(.tertiary)
                        .allowsHitTesting(false)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .padding(24)
        .padding(.top, 8)
        .onChange(of: title) { scheduleSave() }
        .onChange(of: notes) { scheduleSave() }
    }

    @ViewBuilder
    private func metadata(_ record: NoteRecordSnapshot) -> some View {
        if let scheduledItem = scheduledItem(for: record) {
            HStack(spacing: 12) {
                Button { presentScheduleEditor(for: scheduledItem) } label: {
                    Text(
                        scheduledItem.scheduledDate,
                        format: .dateTime.weekday(.abbreviated).month(.abbreviated).day()
                    )
                }
                .accessibilityIdentifier("Notes Date")

                Spacer(minLength: 16)

                if case .event(let event) = scheduledItem {
                    EventTimeLabel(
                        startDate: event.scheduledDate,
                        endDate: event.endDate
                    )
                    .accessibilityIdentifier("Event Time")
                }
            }
            .font(.subheadline)
            .foregroundStyle(.secondary)
            .buttonStyle(.plain)
        }
    }

    private func scheduledItem(
        for record: NoteRecordSnapshot
    ) -> ItemRecordSnapshot? {
        switch record {
        case .todo(let todo): .todo(todo)
        case .event(let event): .event(event)
        case .recurrenceTemplate(let template):
            dataStore.snapshot.currentItem(for: template)
        }
    }

    private var isShowingError: Binding<Bool> {
        Binding(
            get: { errorMessage != nil },
            set: { if !$0 { errorMessage = nil } }
        )
    }

    private func presentScheduleEditor(for item: ItemRecordSnapshot) {
        switch item {
        case .todo(let todo): todoBeingRescheduled = todo
        case .event(let event): eventBeingRescheduled = event
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
