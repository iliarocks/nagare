import SwiftUI

struct ProjectCreateView: View {
    @Environment(\.dismiss) private var dismiss
    @NagareDataStoreEnvironment private var dataStore

    @State private var title = ""
    @State private var notes = ""
    @State private var persistedProjectID: UUID?
    @State private var pendingSave: Task<Void, Never>?
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
        VStack(alignment: .leading, spacing: 16) {
            TextField("Project Title", text: $title)
                .font(.title.weight(.semibold))
                .textFieldStyle(.plain)
                .focused($focusedField, equals: .title)
                .submitLabel(.done)
                .onSubmit {
                    submit()
                }
                .accessibilityIdentifier("Create Project Title")

            NagareDocumentEditor(
                text: $notes,
                accessibilityIdentifier: "Create Project Notes",
                focus: $focusedField
            )
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .nagareComposerContentPadding()
        .nagareComposerFrame(width: 600, height: 280)
        .task {
            focusedField = .title
        }
        .onChange(of: title) {
            scheduleSave()
        }
        .onChange(of: notes) {
            scheduleSave()
        }
        .onDisappear {
            pendingSave?.cancel()
            saveProject()
        }
        .alert("Project Couldn't Be Saved", isPresented: isShowingError) {
            Button("OK", role: .cancel) {
                errorMessage = nil
            }
        } message: {
            Text(errorMessage ?? "An unknown error occurred.")
        }
    }

    private var isShowingError: Binding<Bool> {
        Binding(
            get: { errorMessage != nil },
            set: { if !$0 { errorMessage = nil } }
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

            saveProject()
        }
    }

    private func submit() {
        pendingSave?.cancel()
        guard saveProject(allowingEmptyTitle: true) else { return }
        if let onDismiss {
            onDismiss()
        } else {
            dismiss()
        }
    }

    @discardableResult
    private func saveProject(allowingEmptyTitle: Bool = false) -> Bool {
        guard allowingEmptyTitle || !trimmedTitle.isEmpty else {
            return false
        }

        do {
            let savedNotes = notes.trimmingCharacters(
                in: .whitespacesAndNewlines
            ).isEmpty ? nil : notes
            persistedProjectID = try dataStore.upsertProject(
                ProjectDraft(
                    title: trimmedTitle,
                    notes: savedNotes
                ),
                existingID: persistedProjectID
            )
            return true
        } catch {
            errorMessage = error.localizedDescription
            return false
        }
    }
}
