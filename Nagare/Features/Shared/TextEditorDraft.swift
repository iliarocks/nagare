import Foundation

struct TextEditorDraft: Equatable {
    var title: String
    var notes: String
    private var savedTitle: String
    private var savedNotes: String?

    init(title: String = "", notes: String? = nil) {
        self.title = title
        self.notes = notes ?? ""
        savedTitle = title
        savedNotes = notes
    }

    private var trimmedTitle: String {
        title.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private var normalizedNotes: String? {
        notes.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? nil : notes
    }

    func changes(allowsEmptyTitle: Bool = true) -> [NoteTextChange] {
        var changes: [NoteTextChange] = []
        if trimmedTitle != savedTitle, allowsEmptyTitle || !trimmedTitle.isEmpty {
            changes.append(.title(trimmedTitle))
        }
        if normalizedNotes != savedNotes {
            changes.append(.notes(normalizedNotes))
        }
        return changes
    }

    /// Refresh clean fields independently; a local edit wins a same-field
    /// conflict when it is saved. This never marks an unsaved edit as saved.
    mutating func receive(title: String, notes: String?) {
        if trimmedTitle == savedTitle { self.title = title }
        if normalizedNotes == savedNotes { self.notes = notes ?? "" }
        savedTitle = title
        savedNotes = notes
    }

    mutating func didSave(_ changes: [NoteTextChange]) {
        for change in changes {
            switch change {
            case .title(let value):
                title = value
                savedTitle = value
            case .notes(let value):
                notes = value ?? ""
                savedNotes = value
            }
        }
    }
}
