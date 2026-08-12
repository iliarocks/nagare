import SwiftData
import SwiftUI

struct ProjectCreateView: View {
    private enum Field: Hashable {
        case title
        case notes
    }

    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss

    @State private var title = ""
    @State private var notes = ""
    @State private var persistedProject: Project?
    @State private var pendingSave: Task<Void, Never>?
    @State private var errorMessage: String?
    @FocusState private var focusedField: Field?

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

            ZStack(alignment: .topLeading) {
                TextEditor(text: $notes)
                    .scrollContentBackground(.hidden)
                    .padding(.horizontal, -5)
                    .focused($focusedField, equals: .notes)
                    .accessibilityIdentifier("Create Project Notes")

                if notes.isEmpty {
                    Text("Notes")
                        .foregroundStyle(.tertiary)
                        .allowsHitTesting(false)
            }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .padding(24)
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
            let projectToPersist: Project

            if let persistedProject {
                if persistedProject.title != trimmedTitle
                    || persistedProject.notes != savedNotes {
                    persistedProject.title = trimmedTitle
                    persistedProject.notes = savedNotes
                    try SwiftDataTransaction.save(modelContext)
                }
                return true
            } else {
                let order = try ProjectOrdering.nextOrder(
                    isPriority: false,
                    in: modelContext
                )
                let project = Project(
                    title: trimmedTitle,
                    notes: savedNotes,
                    isPriority: false,
                    order: order
                )
                modelContext.insert(project)
                projectToPersist = project
            }
            try SwiftDataTransaction.save(modelContext)
            persistedProject = projectToPersist
            return true
        } catch {
            modelContext.rollback()
            errorMessage = error.localizedDescription
            return false
        }
    }
}
