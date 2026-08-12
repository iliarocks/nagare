import SwiftData
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

    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss

    @Query private var projects: [Project]

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
    @State private var selectedProject: Project?
    @State private var isShowingDetails = false
    @State private var fieldToRestoreAfterDetails = Field.title
    @State private var persistedItem: Item?
    @State private var pendingSave: Task<Void, Never>?
    @State private var errorMessage: String?
    @FocusState private var focusedField: Field?

    private let onDismiss: (() -> Void)?

    init(
        project: Project? = nil,
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
                    .scrollContentBackground(.hidden)
                    .padding(.horizontal, -5)
                    .focused($focusedField, equals: .notes)
                    .accessibilityIdentifier("Create Notes")

                if notes.isEmpty {
                    Text("Notes")
                        .foregroundStyle(.tertiary)
                        .allowsHitTesting(false)
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

            if let persistedItem {
                if persistedType(of: persistedItem) == itemType {
                    try update(persistedItem, rule: rule)
                } else {
                    self.persistedItem = try replace(
                        persistedItem,
                        rule: rule
                    )
                }
            } else {
                persistedItem = try createPersistedItem(rule: rule)
            }
            return true
        } catch {
            modelContext.rollback()
            errorMessage = error.localizedDescription
            return false
        }
    }

    private func createPersistedItem(
        rule: RecurrenceRule?
    ) throws -> Item {
        let order = try ItemOrdering.nextOrder(in: modelContext)

        switch itemType {
        case .todo:
            let todo = Todo(
                title: trimmedTitle,
                notes: savedNotes,
                scheduledDate: scheduledDate,
                order: order
            )
            modelContext.insert(todo)
            try ProjectMembership.prepare(
                .todo(todo),
                for: selectedProject,
                in: modelContext
            )
            try persistRecurrence(for: todo, rule: rule)
            return .todo(todo)

        case .event:
            let event = Event(
                title: trimmedTitle,
                notes: savedNotes,
                scheduledDate: eventScheduledDate,
                endDate: eventEndDate,
                order: order
            )
            modelContext.insert(event)
            try ProjectMembership.prepare(
                .event(event),
                for: selectedProject,
                in: modelContext
            )
            try persistRecurrence(for: event, rule: rule)
            return .event(event)
        }
    }

    private func update(
        _ item: Item,
        rule: RecurrenceRule?
    ) throws {
        let calendar = Calendar.autoupdatingCurrent

        switch item {
        case .todo(let todo):
            if !calendar.isDate(
                todo.scheduledDate,
                inSameDayAs: scheduledDate
            ) {
                todo.order = try ItemOrdering.nextOrder(in: modelContext)
            }
            todo.title = trimmedTitle
            todo.notes = savedNotes
            todo.scheduledDate = calendar.startOfDay(for: scheduledDate)
            try ProjectMembership.prepare(
                .todo(todo),
                for: selectedProject,
                in: modelContext
            )
            try persistRecurrence(for: todo, rule: rule)

        case .event(let event):
            if !calendar.isDate(
                event.scheduledDate,
                inSameDayAs: eventScheduledDate
            ) {
                event.order = try ItemOrdering.nextOrder(in: modelContext)
            }
            event.title = trimmedTitle
            event.notes = savedNotes
            event.scheduledDate = eventScheduledDate
            event.endDate = eventEndDate
            try ProjectMembership.prepare(
                .event(event),
                for: selectedProject,
                in: modelContext
            )
            try persistRecurrence(for: event, rule: rule)
        }
    }

    private func replace(
        _ item: Item,
        rule: RecurrenceRule?
    ) throws -> Item {
        let previousProject = item.project
        let previousProjectOrder = item.projectOrder
        let order = item.order
        let createdAt: Date

        switch item {
        case .todo(let todo):
            createdAt = todo.createdAt
            if let template = todo.recurrenceTemplate {
                modelContext.delete(template)
            }
            modelContext.delete(todo)
        case .event(let event):
            createdAt = event.createdAt
            if let template = event.recurrenceTemplate {
                modelContext.delete(template)
            }
            modelContext.delete(event)
        }

        switch itemType {
        case .todo:
            let todo = Todo(
                title: trimmedTitle,
                notes: savedNotes,
                scheduledDate: scheduledDate,
                createdAt: createdAt,
                order: order,
                projectOrder: previousProjectOrder
            )
            todo.project = previousProject
            modelContext.insert(todo)
            try ProjectMembership.prepare(
                .todo(todo),
                for: selectedProject,
                in: modelContext
            )
            try persistRecurrence(for: todo, rule: rule)
            return .todo(todo)

        case .event:
            let event = Event(
                title: trimmedTitle,
                notes: savedNotes,
                scheduledDate: eventScheduledDate,
                endDate: eventEndDate,
                createdAt: createdAt,
                order: order,
                projectOrder: previousProjectOrder
            )
            event.project = previousProject
            modelContext.insert(event)
            try ProjectMembership.prepare(
                .event(event),
                for: selectedProject,
                in: modelContext
            )
            try persistRecurrence(for: event, rule: rule)
            return .event(event)
        }
    }

    private func persistRecurrence(
        for todo: Todo,
        rule: RecurrenceRule?
    ) throws {
        if let template = todo.recurrenceTemplate {
            template.title = trimmedTitle
            template.notes = savedNotes
            if let rule {
                try RecurrencePersistence.updateTemplate(
                    template,
                    rule: rule,
                    in: modelContext
                )
            } else {
                try RecurrencePersistence.deleteTemplate(
                    template,
                    in: modelContext
                )
            }
        } else if let rule {
            _ = try RecurrencePersistence.createTemplate(
                for: todo,
                rule: rule,
                in: modelContext
            )
        } else {
            try SwiftDataTransaction.save(modelContext)
        }
    }

    private func persistRecurrence(
        for event: Event,
        rule: RecurrenceRule?
    ) throws {
        if let template = event.recurrenceTemplate {
            template.title = trimmedTitle
            template.notes = savedNotes
            if let rule {
                try RecurrencePersistence.updateTemplate(
                    template,
                    rule: rule,
                    eventStartTimeSeconds: wallTimeSeconds(
                        event.scheduledDate
                    ),
                    eventEndTimeSeconds: event.endDate.map(
                        wallTimeSeconds
                    ),
                    in: modelContext
                )
            } else {
                try RecurrencePersistence.deleteTemplate(
                    template,
                    in: modelContext
                )
            }
        } else if let rule {
            _ = try RecurrencePersistence.createTemplate(
                for: event,
                rule: rule,
                in: modelContext
            )
        } else {
            try SwiftDataTransaction.save(modelContext)
        }
    }

    private func persistedType(of item: Item) -> ItemType {
        switch item {
        case .todo: .todo
        case .event: .event
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
