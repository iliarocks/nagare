import SwiftData
import SwiftUI

enum RecurrenceEditorTarget: Identifiable {
    case todo(Todo)
    case event(Event)
    case template(RecurrenceTemplate)

    var id: String {
        switch self {
        case .todo(let todo): "todo-\(todo.id)"
        case .event(let event): "event-\(event.id)"
        case .template(let template): "template-\(template.id)"
        }
    }

    var existingTemplate: RecurrenceTemplate? {
        switch self {
        case .todo(let todo): todo.recurrenceTemplate
        case .event(let event): event.recurrenceTemplate
        case .template(let template): template
        }
    }
}

struct RecurrenceEditor: View {
    private struct InitialValues {
        let form: RecurrenceFormState
        let itemType: RecurrenceItemType
        let referenceDate: Date
        let startTime: Date
        let includesEndTime: Bool
        let endTime: Date
        let errorMessage: String?
    }

    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext

    let target: RecurrenceEditorTarget
    private let itemType: RecurrenceItemType
    private let referenceDate: Date
    private let initialErrorMessage: String?

    @State private var form: RecurrenceFormState
    @State private var startTime: Date
    @State private var includesEndTime: Bool
    @State private var endTime: Date
    @State private var errorMessage: String?

    init(target: RecurrenceEditorTarget) {
        self.target = target
        let values = Self.initialValues(for: target)
        itemType = values.itemType
        referenceDate = values.referenceDate
        initialErrorMessage = values.errorMessage
        _form = State(initialValue: values.form)
        _startTime = State(initialValue: values.startTime)
        _includesEndTime = State(initialValue: values.includesEndTime)
        _endTime = State(initialValue: values.endTime)
        _errorMessage = State(initialValue: nil)
    }

    var body: some View {
        NavigationStack {
            Form {
                RecurrenceFields(
                    state: $form,
                    itemType: itemType,
                    referenceDate: referenceDate,
                    showsToggle: false
                )

                if itemType == .event {
                    Section {
                        LabeledContent("Time") {
                            HStack(spacing: 8) {
                                DatePicker(
                                    "Start Time",
                                    selection: $startTime,
                                    displayedComponents: .hourAndMinute
                                )
                                .labelsHidden()

                                if includesEndTime {
                                    Text("–")
                                        .foregroundStyle(.secondary)

                                    DatePicker(
                                        "End Time",
                                        selection: $endTime,
                                        displayedComponents: .hourAndMinute
                                    )
                                    .labelsHidden()
                                }

                                Button {
                                    includesEndTime.toggle()
                                } label: {
                                    Label(
                                        includesEndTime
                                            ? "Remove End Time"
                                            : "Add End Time",
                                        systemImage: includesEndTime
                                            ? "minus.circle.fill"
                                            : "plus.circle"
                                    )
                                    .labelStyle(.iconOnly)
                                }
                                .buttonStyle(.plain)
                            }
                        }
                    } header: {
                        Text("Future Event Time")
                    } footer: {
                        if !isEventTimeValid {
                            Text("The end time must not be earlier than the start time.")
                                .foregroundStyle(.red)
                        }
                    }
                }
            }
            .navigationTitle(
                target.existingTemplate == nil ? "Add Repeat" : "Edit Repeat"
            )
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        dismiss()
                    }
                }

                ToolbarItem(placement: .confirmationAction) {
                    Button(action: save) {
                        Label("Save Repeat", systemImage: "checkmark")
                            .labelStyle(.iconOnly)
                    }
                    .tint(.accentColor)
                    .disabled(!canSave)
                }
            }
            .alert("Repeat Couldn't Be Saved", isPresented: isShowingError) {
                Button("OK", role: .cancel) {
                    errorMessage = nil
                }
            } message: {
                Text(errorMessage ?? "An unknown error occurred.")
            }
            .task {
                if let initialErrorMessage {
                    errorMessage = initialErrorMessage
                }
            }
        }
    }

    private var isEventTimeValid: Bool {
        guard itemType == .event && includesEndTime else {
            return true
        }
        return wallTimeSeconds(endTime) >= wallTimeSeconds(startTime)
    }

    private var canSave: Bool {
        initialErrorMessage == nil && form.isValid && isEventTimeValid
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

    private func save() {
        guard initialErrorMessage == nil else {
            errorMessage = initialErrorMessage
                ?? "Nagare couldn't load this repeat rule. (RECURRENCE-UI-006)"
            return
        }
        guard form.isValid else {
            errorMessage = "Choose at least one valid repeat day. (RECURRENCE-UI-001)"
            return
        }
        guard isEventTimeValid else {
            errorMessage = "The future Event end time cannot be earlier than its start time. (RECURRENCE-UI-002)"
            return
        }

        do {
            guard let rule = try form.rule(referenceDate: referenceDate) else {
                throw RecurrenceEditorError.missingRule
            }

            switch target {
            case .todo(let todo):
                if let template = todo.recurrenceTemplate {
                    try update(template, rule: rule)
                } else {
                    _ = try RecurrencePersistence.createTemplate(
                        for: todo,
                        rule: rule,
                        in: modelContext
                    )
                }
            case .event(let event):
                if let template = event.recurrenceTemplate {
                    try update(template, rule: rule)
                } else {
                    _ = try RecurrencePersistence.createTemplate(
                        for: event,
                        rule: rule,
                        in: modelContext
                    )
                }
            case .template(let template):
                try update(template, rule: rule)
            }

            dismiss()
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func update(
        _ template: RecurrenceTemplate,
        rule: RecurrenceRule
    ) throws {
        try RecurrencePersistence.updateTemplate(
            template,
            rule: rule,
            eventStartTimeSeconds: itemType == .event
                ? wallTimeSeconds(startTime)
                : nil,
            eventEndTimeSeconds: itemType == .event && includesEndTime
                ? wallTimeSeconds(endTime)
                : nil,
            in: modelContext
        )
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

    private static func initialValues(
        for target: RecurrenceEditorTarget
    ) -> InitialValues {
        let calendar = Calendar.autoupdatingCurrent
        let now = Date.now

        do {
            let itemType = try itemType(for: target)
            let referenceDate = try referenceDate(for: target)
            let form: RecurrenceFormState
            if let template = target.existingTemplate {
                form = try .existing(template, calendar: calendar)
            } else {
                form = .enabled(
                    for: itemType,
                    referenceDate: referenceDate,
                    calendar: calendar
                )
            }

            let times = try eventTimes(
                for: target,
                itemType: itemType,
                fallback: now,
                calendar: calendar
            )
            return InitialValues(
                form: form,
                itemType: itemType,
                referenceDate: referenceDate,
                startTime: times.start,
                includesEndTime: times.end != nil,
                endTime: times.end
                    ?? calendar.date(byAdding: .hour, value: 1, to: times.start)
                    ?? times.start,
                errorMessage: nil
            )
        } catch {
            return InitialValues(
                form: .enabled(
                    for: .todo,
                    referenceDate: now,
                    calendar: calendar
                ),
                itemType: .todo,
                referenceDate: now,
                startTime: now,
                includesEndTime: false,
                endTime: calendar.date(byAdding: .hour, value: 1, to: now) ?? now,
                errorMessage: error.localizedDescription
            )
        }
    }

    private static func itemType(
        for target: RecurrenceEditorTarget
    ) throws -> RecurrenceItemType {
        switch target {
        case .todo:
            return .todo
        case .event:
            return .event
        case .template(let template):
            guard let itemType = template.itemType else {
                throw RecurrencePersistenceError.wrongItemType
            }
            return itemType
        }
    }

    private static func referenceDate(
        for target: RecurrenceEditorTarget
    ) throws -> Date {
        switch target {
        case .todo(let todo):
            return todo.scheduledDate
        case .event(let event):
            return event.scheduledDate
        case .template(let template):
            switch template.itemType {
            case .todo:
                guard let todo = template.todoOccurrences.first(where: {
                    $0.id == template.currentItemID && $0.completedAt == nil
                }) else {
                    throw VirtualItemProjectionError.missingCurrentOccurrence
                }
                return todo.scheduledDate
            case .event:
                guard let event = template.eventOccurrences.first(where: {
                    $0.id == template.currentItemID
                }) else {
                    throw VirtualItemProjectionError.missingCurrentOccurrence
                }
                return event.scheduledDate
            case nil:
                throw RecurrencePersistenceError.wrongItemType
            }
        }
    }

    private static func eventTimes(
        for target: RecurrenceEditorTarget,
        itemType: RecurrenceItemType,
        fallback: Date,
        calendar: Calendar
    ) throws -> (start: Date, end: Date?) {
        guard itemType == .event else {
            return (fallback, nil)
        }

        if let template = target.existingTemplate {
            guard let startSeconds = template.startTimeSeconds else {
                throw RecurrencePersistenceError.missingEventStartTime
            }
            return (
                try timeDate(startSeconds, calendar: calendar),
                try template.endTimeSeconds.map {
                    try timeDate($0, calendar: calendar)
                }
            )
        }

        guard case .event(let event) = target else {
            throw RecurrencePersistenceError.wrongItemType
        }
        return (event.scheduledDate, event.endDate)
    }

    private static func timeDate(
        _ seconds: Int,
        calendar: Calendar
    ) throws -> Date {
        guard (0..<86_400).contains(seconds),
              let date = calendar.date(
                bySettingHour: seconds / 3_600,
                minute: seconds % 3_600 / 60,
                second: seconds % 60,
                of: .now
              ) else {
            throw RecurrencePersistenceError.invalidEventTime
        }
        return date
    }
}

enum RecurrenceEditorError: Error, LocalizedError {
    case missingRule

    var errorDescription: String? {
        "Nagare couldn't construct the repeat rule. (RECURRENCE-UI-003)"
    }
}
