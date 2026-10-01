import Foundation

struct RecurrenceEditorDraft: Equatable {
    var form: RecurrenceFormState
    private(set) var referenceDate: Date
    private(set) var loadError: String?
    private var savedForm: RecurrenceFormState

    init(template: RecurrenceTemplateRecordSnapshot) {
        do {
            guard let date = template.currentScheduledDate else {
                throw RecurrenceEditorError.missingCurrentOccurrence
            }
            referenceDate = date
            form = try RecurrenceFormState.existing(template)
            loadError = nil
        } catch {
            referenceDate = .now
            form = .enabled(referenceDate: referenceDate)
            loadError = error.localizedDescription
        }
        savedForm = form
    }

    mutating func receive(_ template: RecurrenceTemplateRecordSnapshot) {
        let latest = Self(template: template)
        if form == savedForm || loadError != nil {
            self = latest
        } else {
            savedForm = latest.form
        }
    }

    mutating func save(_ commit: (RecurrenceRule) throws -> Void) throws {
        guard loadError == nil, form.isValid, form != savedForm else { return }
        guard let rule = try form.rule(referenceDate: referenceDate) else {
            throw RecurrenceEditorError.missingRule
        }
        try commit(rule)
        savedForm = form
    }
}
