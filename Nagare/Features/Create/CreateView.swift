import SwiftUI

struct CreateView: View {
    private enum Field: Hashable {
        case title
        case notes
    }

    private enum ItemType: String, CaseIterable, Identifiable {
        case todo
        case event

        var id: Self { self }

        var title: String {
            switch self {
            case .todo: "Todo"
            case .event: "Event"
            }
        }

    }

    @Environment(\.dismiss) private var dismiss
    @NagareDataStoreEnvironment private var dataStore

    @State private var itemType = ItemType.todo
    @State private var title = ""
    @State private var notes = ""
    @State private var scheduledDate = Date.now
    @State private var startTime = Date.now
    @State private var includesEndTime = false
    @State private var endTime =
        Calendar.autoupdatingCurrent.date(
            byAdding: .hour,
            value: 1,
            to: .now
        ) ?? .now
    @State private var recurrence = RecurrenceFormState.disabled
    @State private var selectedProject: ProjectRecordSnapshot?
    @State private var isShowingDetails = false
    @State private var fieldToRestoreAfterDetails = Field.title
    @State private var persistedItemID: ItemID?
    @State private var pendingSave: Task<Void, Never>?
    @State private var errorMessage: String?
    @FocusState private var focusedField: Field?

    private let onDismiss: (() -> Void)?

    private var projects: [ProjectRecordSnapshot] {
        dataStore.projects
    }

    init(
        project: ProjectRecordSnapshot? = nil,
        onDismiss: (() -> Void)? = nil
    ) {
        _selectedProject = State(initialValue: project)
        self.onDismiss = onDismiss
    }

    private var trimmedTitle: String {
        title.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private var savedNotes: String? {
        notes.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            ? nil
            : notes
    }

    private var eventScheduledDate: Date {
        ScheduleDateTime.combining(scheduledDate, with: startTime)
    }

    private var eventEndDate: Date? {
        guard includesEndTime else {
            return nil
        }
        return ScheduleDateTime.combining(scheduledDate, with: endTime)
    }

    private var isScheduleValid: Bool {
        guard let eventEndDate else {
            return true
        }
        return eventEndDate > eventScheduledDate
    }

    private var recurrenceItemType: RecurrenceItemType {
        itemType == .todo ? .todo : .event
    }

    private var isDraftStructurallyValid: Bool {
        isScheduleValid && recurrence.isValid
    }

    var body: some View {
        composer
            .presentationDetents([.large])
            .presentationDragIndicator(.visible)
            .sheet(
                isPresented: $isShowingDetails,
                onDismiss: restoreFocusAfterDetails
            ) {
                details
                    .presentationDetents([.large])
                    .presentationDragIndicator(.visible)
            }
            .alert(
                "\(itemType.title) Couldn't Be Saved",
                isPresented: isShowingError
            ) {
                Button("OK", role: .cancel) {
                    errorMessage = nil
                }
            } message: {
                Text(errorMessage ?? "An unknown error occurred.")
            }
            .task {
                focusedField = .title
            }
            .onChange(of: title) {
                scheduleSave()
            }
            .onChange(of: notes) {
                scheduleSave()
            }
            .onChange(of: itemType) {
                let referenceDate = itemType == .todo
                    ? scheduledDate
                    : eventScheduledDate
                recurrence.prepare(
                    for: recurrenceItemType,
                    referenceDate: referenceDate
                )
                recurrence.rebaseReference(to: referenceDate)
                scheduleSave()
            }
            .onChange(of: scheduledDate) {
                if itemType == .todo {
                    recurrence.rebaseReference(to: scheduledDate)
                }
                scheduleSave()
            }
            .onChange(of: eventScheduledDate) {
                if itemType == .event {
                    recurrence.rebaseReference(to: eventScheduledDate)
                }
                scheduleSave()
            }
            .onChange(of: includesEndTime) {
                scheduleSave()
            }
            .onChange(of: endTime) {
                scheduleSave()
            }
            .onChange(of: selectedProject?.id) {
                scheduleSave()
            }
            .onChange(of: recurrence) {
                scheduleSave()
            }
            .onDisappear {
                pendingSave?.cancel()
                saveDraft()
            }
    }

    private var composer: some View {
        VStack(alignment: .leading, spacing: 16) {
            TextField(
                itemType == .todo
                    ? "What needs doing?"
                    : "What's happening?",
                text: $title
            )
            .font(.title.weight(.semibold))
            .textFieldStyle(.plain)
            .focused($focusedField, equals: .title)
            .submitLabel(.done)
            .onSubmit {
                submit()
            }
            .accessibilityIdentifier("Create Title")

            ZStack(alignment: .topLeading) {
                TextEditor(text: $notes)
                    .nagareDocumentEditorStyle()
                    .focused($focusedField, equals: .notes)
                    .accessibilityIdentifier("Create Notes")

                if notes.isEmpty {
                    Text("Notes")
                        .nagareDocumentPlaceholderStyle()
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)

            Divider()

            Button {
                fieldToRestoreAfterDetails = focusedField ?? .title
                focusedField = nil
                isShowingDetails = true
            } label: {
                HStack(spacing: 12) {
                    Text(detailsSummary)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                        .frame(maxWidth: .infinity, alignment: .leading)

                    Image(systemName: "chevron.right")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.tertiary)
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityIdentifier("Create Details")
            .padding(.vertical, 8)
        }
        .padding(.horizontal, 24)
        .padding(.top, 32)
        .padding(.bottom, 16)
        .nagareComposerFrame(width: 620, height: 400)
    }

    private var details: some View {
        Form {
            Section {
                Picker("Type", selection: $itemType) {
                    ForEach(ItemType.allCases) { type in
                        Text(type.title)
                            .tag(type)
                    }
                }
                .pickerStyle(.menu)
                .accessibilityIdentifier("Create Item Type")
            }

            Section {
                if itemType == .event {
                    ScheduleFields(
                        date: $scheduledDate,
                        startTime: $startTime,
                        includesEndTime: $includesEndTime,
                        endTime: $endTime
                    )
                } else {
                    DatePicker(
                        "Date",
                        selection: $scheduledDate,
                        in: Calendar.autoupdatingCurrent.startOfDay(for: .now)...,
                        displayedComponents: .date
                    )
                }
            } footer: {
                if itemType == .event && !isScheduleValid {
                    Text("The end time must be later than the start time.")
                        .foregroundStyle(.red)
                }
            }

            Section {
                ProjectPicker(
                    projects: projects,
                    selectedProject: selectedProject,
                    onSelect: { selectedProject = $0 }
                )
            }

            RecurrenceFields(
                state: $recurrence,
                itemType: recurrenceItemType,
                referenceDate: itemType == .todo
                    ? scheduledDate
                    : eventScheduledDate
            )
        }
        .nagareDetailsForm(height: detailsHeight)
    }

    private var detailsHeight: CGFloat {
        guard recurrence.isEnabled else {
            return itemType == .event ? 360 : 300
        }
        return 540
    }

    private var detailsSummary: String {
        [scheduleSummary, projectSummary, recurrenceSummary]
            .joined(separator: " · ")
    }

    private var scheduleSummary: String {
        let calendar = Calendar.autoupdatingCurrent
        let date: Date
        let includesTime: Bool
        switch itemType {
        case .todo:
            date = scheduledDate
            includesTime = false
        case .event:
            date = eventScheduledDate
            includesTime = true
        }

        let day: String
        if calendar.isDateInToday(date) {
            day = "Today"
        } else if calendar.isDateInTomorrow(date) {
            day = "Tomorrow"
        } else {
            day = date.formatted(date: .abbreviated, time: .omitted)
        }

        guard includesTime else {
            return day
        }
        return "\(day) at \(date.formatted(date: .omitted, time: .shortened))"
    }

    private var projectSummary: String {
        selectedProject?.title ?? "No Project"
    }

    private var recurrenceSummary: String {
        guard recurrence.isEnabled else {
            return "No Repeat"
        }

        let cadence = recurrence.interval == 1
            ? "Every \(recurrence.unit.singularTitle)"
            : "Every \(recurrence.interval) \(recurrence.unit.pluralTitle)"
        return recurrence.mode == .relative
            ? "\(cadence) after completion"
            : cadence
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

            saveDraft()
        }
    }

    private func submit() {
        pendingSave?.cancel()
        guard saveDraft(allowingEmptyTitle: true) else { return }
        if let onDismiss {
            onDismiss()
        } else {
            dismiss()
        }
    }

    private func restoreFocusAfterDetails() {
        restoreFocus(fieldToRestoreAfterDetails)
    }

    private func restoreFocus(_ field: Field) {
        Task { @MainActor in
            await Task.yield()
            guard !isShowingDetails else {
                return
            }
            focusedField = field
        }
    }

    @discardableResult
    private func saveDraft(allowingEmptyTitle: Bool = false) -> Bool {
        guard isDraftStructurallyValid,
              allowingEmptyTitle || !trimmedTitle.isEmpty else {
            return false
        }

        do {
            let referenceDate = itemType == .todo
                ? scheduledDate
                : eventScheduledDate
            let rule = try recurrence.rule(referenceDate: referenceDate)

            persistedItemID = try dataStore.upsertItem(
                ItemDraft(
                    kind: itemType == .todo ? .todo : .event,
                    title: trimmedTitle,
                    notes: savedNotes,
                    scheduledDate: itemType == .todo
                        ? scheduledDate
                        : eventScheduledDate,
                    endDate: itemType == .event ? eventEndDate : nil,
                    projectID: selectedProject?.id,
                    recurrenceRule: rule,
                    eventStartTimeSeconds: itemType == .event
                        ? wallTimeSeconds(eventScheduledDate)
                        : nil,
                    eventEndTimeSeconds: itemType == .event
                        ? eventEndDate.map(wallTimeSeconds)
                        : nil
                ),
                existingID: persistedItemID
            )
            return true
        } catch {
            errorMessage = error.localizedDescription
            return false
        }
    }

    private func wallTimeSeconds(_ date: Date) -> Int {
        let components = Calendar.autoupdatingCurrent.dateComponents(
            [.hour, .minute, .second],
            from: date
        )
        return (components.hour ?? 0) * 3_600
            + (components.minute ?? 0) * 60
            + (components.second ?? 0)
    }

}
