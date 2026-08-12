import SwiftData
import SwiftUI

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

    @Environment(\.modelContext) private var modelContext

    let template: RecurrenceTemplate
    private let itemType: RecurrenceItemType
    private let referenceDate: Date
    private let initialErrorMessage: String?

    @State private var form: RecurrenceFormState
    @State private var startTime: Date
    @State private var includesEndTime: Bool
    @State private var endTime: Date
    @State private var errorMessage: String?
    @State private var pendingSave: Task<Void, Never>?

    init(template: RecurrenceTemplate) {
        self.template = template
        let values = Self.initialValues(for: template)
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
        .scrollIndicators(.hidden)
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
        .onChange(of: form) {
            scheduleSave()
        }
        .onChange(of: startTime) {
            scheduleSave()
        }
        .onChange(of: includesEndTime) {
            scheduleSave()
        }
        .onChange(of: endTime) {
            scheduleSave()
        }
        .onDisappear {
            pendingSave?.cancel()
            save()
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

    private func scheduleSave() {
        pendingSave?.cancel()
        pendingSave = Task {
            do {
                try await Task.sleep(for: .milliseconds(350))
            } catch {
                return
            }
            save()
        }
    }

    private func save() {
        guard canSave else { return }

        do {
            guard let rule = try form.rule(referenceDate: referenceDate) else {
                throw RecurrenceEditorError.missingRule
            }

            try update(template, rule: rule)
        } catch {
            modelContext.rollback()
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
        for template: RecurrenceTemplate
    ) -> InitialValues {
        let calendar = Calendar.autoupdatingCurrent
        let now = Date.now

        do {
            let itemType = try itemType(for: template)
            let referenceDate = try referenceDate(for: template)
            let form = try RecurrenceFormState.existing(
                template,
                calendar: calendar
            )

            let times = try eventTimes(
                for: template,
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
        for template: RecurrenceTemplate
    ) throws -> RecurrenceItemType {
        guard let itemType = template.itemType else {
            throw RecurrencePersistenceError.wrongItemType
        }
        return itemType
    }

    private static func referenceDate(
        for template: RecurrenceTemplate
    ) throws -> Date {
        switch template.itemType {
        case .todo:
            guard let todo = template.todoOccurrences.first(where: {
                $0.id == template.currentItemID && $0.completedAt == nil
            }) else {
                throw RecurrenceEditorError.missingCurrentOccurrence
            }
            return todo.scheduledDate
        case .event:
            guard let event = template.eventOccurrences.first(where: {
                $0.id == template.currentItemID
            }) else {
                throw RecurrenceEditorError.missingCurrentOccurrence
            }
            return event.scheduledDate
        case nil:
            throw RecurrencePersistenceError.wrongItemType
        }
    }

    private static func eventTimes(
        for template: RecurrenceTemplate,
        itemType: RecurrenceItemType,
        fallback: Date,
        calendar: Calendar
    ) throws -> (start: Date, end: Date?) {
        guard itemType == .event else {
            return (fallback, nil)
        }

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
    case missingCurrentOccurrence

    var errorDescription: String? {
        switch self {
        case .missingRule:
            "Nagare couldn't construct the repeat rule. (RECURRENCE-UI-003)"
        case .missingCurrentOccurrence:
            "This repeat is still waiting for its current item to sync. (RECURRENCE-UI-004)"
        }
    }
}
