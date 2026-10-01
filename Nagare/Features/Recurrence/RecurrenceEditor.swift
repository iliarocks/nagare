import SwiftUI

struct RecurrenceEditor: View {
    @NagareDataStoreEnvironment private var dataStore
    let template: RecurrenceTemplateRecordSnapshot

    @State private var draft: RecurrenceEditorDraft
    @State private var errorMessage: String?

    init(template: RecurrenceTemplateRecordSnapshot) {
        self.template = template
        _draft = State(initialValue: RecurrenceEditorDraft(template: template))
    }

    var body: some View {
        Form {
            RecurrenceFields(
                state: $draft.form,
                referenceDate: draft.referenceDate,
                showsToggle: false
            )
        }
        .nagareDetailsForm(height: editorHeight)
        .scrollIndicators(.hidden)
        .animation(.snappy, value: draft.form.mode)
        .animation(.snappy, value: draft.form.unit)
        .animation(.snappy, value: draft.form.repeatUntil != nil)
        .alert("Repeat Couldn't Be Saved", isPresented: isShowingError) {
            Button("OK", role: .cancel) {
                errorMessage = nil
            }
        } message: {
            Text(errorMessage ?? "An unknown error occurred.")
        }
        .task { errorMessage = draft.loadError }
        .onChange(of: dataStore.snapshot.templatesByID[template.id]) { _, latest in
            if let latest { draft.receive(latest) }
        }
        .nagareAutosave(draft.form, after: .milliseconds(350), save: save)
    }

    private var editorHeight: CGFloat {
#if os(macOS)
        var height: CGFloat = 290
#else
        var height: CGFloat = 230
#endif

        if draft.form.repeatUntil != nil {
            height += 100
        }

        guard draft.form.mode == .absolute else {
            return height
        }

        switch draft.form.unit {
        case .day, .year:
            return height
        case .week:
            height += 90
        case .month:
            height += 260
        }
        return min(height, 520)
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
        do {
            try draft.save { rule in
                try dataStore.updateRecurrenceRule(template.id, rule: rule)
            }
        } catch {
            errorMessage = error.localizedDescription
        }
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
