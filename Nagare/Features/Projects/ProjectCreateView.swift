import SwiftData
import SwiftUI

struct ProjectCreateView: View {
    private enum Field: Hashable {
        case title
        case notes
    }

    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext

    @State private var title = ""
    @State private var notes = ""
    @State private var errorMessage: String?
    @FocusState private var focusedField: Field?

    private var trimmedTitle: String {
        title.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    var body: some View {
        NavigationStack {
            VStack(alignment: .leading, spacing: 16) {
                TextField("Project Title", text: $title)
                    .font(.title.weight(.semibold))
                    .focused($focusedField, equals: .title)
                    .submitLabel(.done)
                    .onSubmit {
                        focusedField = nil
                    }
                    .accessibilityIdentifier("Create Project Title")

                ZStack(alignment: .topLeading) {
                    if notes.isEmpty {
                        Text("Notes")
                            .foregroundStyle(.tertiary)
                            .padding(.vertical, 8)
                    }

                    TextEditor(text: $notes)
                        .scrollContentBackground(.hidden)
                        .padding(.horizontal, -5)
                        .focused($focusedField, equals: .notes)
                        .accessibilityIdentifier("Create Project Notes")
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
            .padding()
            .padding([.top, .horizontal], 8)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        dismiss()
                    }
                }

                ToolbarItem(placement: .confirmationAction) {
                    Button(action: create) {
                        Label("Create Project", systemImage: "checkmark")
                            .labelStyle(.iconOnly)
                    }
                    .disabled(trimmedTitle.isEmpty)
                }
            }
            .task {
                focusedField = .title
            }
            .alert("Project Couldn't Be Created", isPresented: isShowingError) {
                Button("OK", role: .cancel) {
                    errorMessage = nil
                }
            } message: {
                Text(errorMessage ?? "An unknown error occurred.")
            }
        }
    }

    private var isShowingError: Binding<Bool> {
        Binding(
            get: { errorMessage != nil },
            set: { if !$0 { errorMessage = nil } }
        )
    }

    private func create() {
        guard !trimmedTitle.isEmpty else {
            return
        }

        do {
            let order = try ProjectOrdering.nextOrder(
                isPriority: false,
                in: modelContext
            )
            let savedNotes = notes.trimmingCharacters(
                in: .whitespacesAndNewlines
            ).isEmpty ? nil : notes
            modelContext.insert(
                Project(
                    title: trimmedTitle,
                    notes: savedNotes,
                    isPriority: false,
                    order: order
                )
            )
            try modelContext.save()
            dismiss()
        } catch {
            modelContext.rollback()
            errorMessage = error.localizedDescription
        }
    }
}
