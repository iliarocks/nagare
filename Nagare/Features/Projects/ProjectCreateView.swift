import SwiftUI

struct ProjectCreateView: View {
    @Environment(\.dismiss) private var dismiss
    @NagareDataStoreEnvironment private var dataStore

    @State private var title = ""
    @State private var notes = ""
    @State private var errorMessage: String?
    @FocusState private var focusedField: NagareEditorField?

    private let onDismiss: (() -> Void)?

    init(onDismiss: (() -> Void)? = nil) {
        self.onDismiss = onDismiss
    }

    private var trimmedTitle: String {
        title.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    var body: some View {
        NavigationStack {
            editorContent
                .nagareProjectCreationChrome(
                    isSubmitDisabled: trimmedTitle.isEmpty,
                    onClose: close,
                    onSubmit: submit
                )
        }
        .task {
            focusedField = .title
        }
        .alert("Project Couldn't Be Saved", isPresented: isShowingError) {
            Button("OK", role: .cancel) {
                errorMessage = nil
            }
        } message: {
            Text(errorMessage ?? "An unknown error occurred.")
        }
    }

    private var editorContent: some View {
        NagareDocumentComposerLayout {
            TextField("Project Title", text: $title)
                .font(.title.weight(.semibold))
                .textFieldStyle(.plain)
                .focused($focusedField, equals: .title)
                .submitLabel(.done)
                .onSubmit {
                    submit()
                }
                .accessibilityIdentifier("Create Project Title")
        } document: {
            NagareDocumentEditor(
                text: $notes,
                accessibilityIdentifier: "Create Project Notes",
                focus: $focusedField
            )
        }
        .nagareComposerFrame(width: 600, height: 280)
    }

    private var isShowingError: Binding<Bool> {
        Binding(
            get: { errorMessage != nil },
            set: { if !$0 { errorMessage = nil } }
        )
    }

    private func submit() {
        guard saveProject() else { return }
        close()
    }

    private func close() {
        focusedField = nil
        if let onDismiss {
            onDismiss()
        } else {
            dismiss()
        }
    }

    @discardableResult
    private func saveProject() -> Bool {
        guard !trimmedTitle.isEmpty else { return false }

        do {
            let savedNotes = notes.trimmingCharacters(
                in: .whitespacesAndNewlines
            ).isEmpty ? nil : notes
            try dataStore.upsertProject(
                ProjectDraft(
                    title: trimmedTitle,
                    notes: savedNotes
                ),
                existingID: nil
            )
            return true
        } catch {
            errorMessage = error.localizedDescription
            return false
        }
    }
}
