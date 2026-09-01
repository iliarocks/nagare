import SwiftUI

struct RecurrenceEditor: View {
    private struct InitialValues {
        let form: RecurrenceFormState
        let referenceDate: Date
        let errorMessage: String?
    }

    @NagareDataStoreEnvironment private var dataStore

    let template: RecurrenceTemplateRecordSnapshot
    private let referenceDate: Date
    private let initialErrorMessage: String?

    @State private var form: RecurrenceFormState
    @State private var errorMessage: String?
    @State private var pendingSave: Task<Void, Never>?

    init(template: RecurrenceTemplateRecordSnapshot) {
        self.template = template
        let values = Self.initialValues(for: template)
        referenceDate = values.referenceDate
        initialErrorMessage = values.errorMessage
        _form = State(initialValue: values.form)
        _errorMessage = State(initialValue: nil)
    }

    var body: some View {
        Form {
            RecurrenceFields(
                state: $form,
                referenceDate: referenceDate,
                showsToggle: false
            )
        }
        .nagareDetailsForm(height: editorHeight)
        .scrollIndicators(.hidden)
        .animation(.snappy, value: form.mode)
        .animation(.snappy, value: form.unit)
        .animation(.snappy, value: form.repeatUntil != nil)
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
        .onDisappear {
            pendingSave?.cancel()
            save()
        }
    }

    private var editorHeight: CGFloat {
#if os(macOS)
        var height: CGFloat = 290
#else
        var height: CGFloat = 230
#endif

        if form.repeatUntil != nil {
            height += 100
        }

        guard form.mode == .absolute else {
            return height
        }

        switch form.unit {
        case .day, .year:
            return height
        case .week:
            height += 90
        case .month:
            height += 260
        }
        return min(height, 520)
    }

    private var canSave: Bool {
        initialErrorMessage == nil && form.isValid
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

            try dataStore.updateRecurrenceTemplate(
                template.id,
                rule: rule,
                startTimeSeconds: template.startTimeSeconds,
                endTimeSeconds: template.endTimeSeconds
            )
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private static func initialValues(
        for template: RecurrenceTemplateRecordSnapshot
    ) -> InitialValues {
        let calendar = Calendar.autoupdatingCurrent
        let now = Date.now

        do {
            let referenceDate = try referenceDate(for: template)
            let form = try RecurrenceFormState.existing(
                template,
                calendar: calendar
            )
            return InitialValues(
                form: form,
                referenceDate: referenceDate,
                errorMessage: nil
            )
        } catch {
            return InitialValues(
                form: .enabled(
                    referenceDate: now,
                    calendar: calendar
                ),
                referenceDate: now,
                errorMessage: error.localizedDescription
            )
        }
    }

    private static func referenceDate(
        for template: RecurrenceTemplateRecordSnapshot
    ) throws -> Date {
        guard let date = template.currentScheduledDate else {
            throw RecurrenceEditorError.missingCurrentOccurrence
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
