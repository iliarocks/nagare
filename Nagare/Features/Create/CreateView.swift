import SwiftUI

struct CreateView: View {
    private enum PresentedEditor: String, Identifiable {
        case schedule
        case repeatPattern

        var id: Self { self }
    }

    @Environment(\.dismiss) private var dismiss
    @NagareDataStoreEnvironment private var dataStore

    @State private var title = ""
    @State private var notes = ""
    @State private var scheduledDate = Date.now
    @State private var includesTime = false
    @State private var startTime = Date.now
    @State private var includesEndTime = false
    @State private var endTime =
        Calendar.autoupdatingCurrent.date(
            byAdding: .hour,
            value: 1,
            to: .now
        ) ?? .now
    @State private var recurrence = RecurrenceFormState.disabled
    @State private var selectedProject: ProjectRecordSnapshot?
    @State private var presentedEditor: PresentedEditor?
    @State private var fieldToRestoreAfterEditor = NagareEditorField.title
    @State private var persistedItemID: ItemID?
    @State private var errorMessage: String?
    @FocusState private var focusedField: NagareEditorField?

    private let onDismiss: (() -> Void)?

    private var projects: [ProjectRecordSnapshot] {
        dataStore.projects
    }

    init(
        project: ProjectRecordSnapshot? = nil,
        onDismiss: (() -> Void)? = nil
    ) {
        _selectedProject = State(initialValue: project)
        self.onDismiss = onDismiss
    }

    private var trimmedTitle: String {
        title.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private var savedNotes: String? {
        notes.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            ? nil
            : notes
    }

    private var resolvedScheduledDate: Date {
        if includesTime {
            return ScheduleDateTime.combining(scheduledDate, with: startTime)
        }
        return Calendar.autoupdatingCurrent.startOfDay(for: scheduledDate)
    }

    private var resolvedEndDate: Date? {
        guard includesTime && includesEndTime else { return nil }
        return ScheduleDateTime.combining(scheduledDate, with: endTime)
    }

    private var isScheduleValid: Bool {
        guard let resolvedEndDate else { return true }
        return resolvedEndDate > resolvedScheduledDate
    }

    private var isDraftStructurallyValid: Bool {
        isScheduleValid && recurrence.isValid
    }

    var body: some View {
        composer
            .nagareSheetDetents([.large])
            .presentationDragIndicator(.visible)
            .nagareModal(
                item: $presentedEditor,
                onDismiss: restoreFocusAfterEditor
            ) { editor in
                presentedView(editor)
            }
            .alert(
                "Todo Couldn't Be Saved",
                isPresented: isShowingError
            ) {
                Button("OK", role: .cancel) { errorMessage = nil }
            } message: {
                Text(errorMessage ?? "An unknown error occurred.")
            }
            .task {
                focusedField = .title
            }
            .onChange(of: includesTime) {
                let referenceDate = resolvedScheduledDate
                recurrence.prepare(
                    referenceDate: referenceDate
                )
                recurrence.rebaseReference(to: referenceDate)
            }
            .onChange(of: scheduledDate) {
                recurrence.rebaseReference(to: resolvedScheduledDate)
            }
            .onChange(of: resolvedScheduledDate) {
                recurrence.rebaseReference(to: resolvedScheduledDate)
            }
    }

    private var composer: some View {
        NavigationStack {
            composerContent
                .nagareEditorMetadataChrome(
                    scheduleTitle: ScheduleToolbarPresentation.title(
                        scheduledDate: resolvedScheduledDate,
                        includesTime: includesTime,
                        endDate: resolvedEndDate
                    ),
                    scheduleAccessibilityIdentifier: "Create Date",
                    projects: projects,
                    selectedProject: selectedProject,
                    hasRepeat: recurrence.isEnabled,
                    projectAccessibilityIdentifier: "Create Project",
                    repeatAccessibilityIdentifier: "Create Repeat",
                    submitAccessibilityIdentifier: "Create Submit",
                    isSubmitDisabled:
                        trimmedTitle.isEmpty || !isDraftStructurallyValid,
                    onSchedule: { present(.schedule) },
                    onSelectProject: { selectedProject = $0 },
                    onRepeat: { present(.repeatPattern) },
                    onSubmit: submit
                )
        }
    }

    private var composerContent: some View {
        NagareDocumentComposerLayout {
            TextField(
                "What needs doing?",
                text: $title
            )
            .font(.title.weight(.semibold))
            .textFieldStyle(.plain)
            .focused($focusedField, equals: .title)
            .submitLabel(.done)
            .onSubmit { submit() }
            .accessibilityIdentifier("Create Title")
        } document: {
            NagareDocumentEditor(
                text: $notes,
                accessibilityIdentifier: "Create Notes",
                focus: $focusedField
            )
        }
        .nagareComposerFrame(width: 620, height: 400)
    }

    @ViewBuilder
    private func presentedView(_ editor: PresentedEditor) -> some View {
        switch editor {
        case .schedule:
            DraftScheduleEditor(
                scheduledDate: $scheduledDate,
                includesTime: $includesTime,
                startTime: $startTime,
                includesEndTime: $includesEndTime,
                endTime: $endTime
            )
        case .repeatPattern:
            DraftRecurrenceEditor(
                state: $recurrence,
                referenceDate: resolvedScheduledDate
            )
            .nagareSheetDetents([.medium])
            .presentationDragIndicator(.visible)
        }
    }

    private var isShowingError: Binding<Bool> {
        Binding(
            get: { errorMessage != nil },
            set: { if !$0 { errorMessage = nil } }
        )
    }

    private func submit() {
        guard saveDraft() else { return }
        if let onDismiss {
            onDismiss()
        } else {
            dismiss()
        }
    }

    private func present(_ editor: PresentedEditor) {
        fieldToRestoreAfterEditor = focusedField ?? .title
        focusedField = nil
        presentedEditor = editor
    }

    private func restoreFocusAfterEditor() {
        restoreFocus(fieldToRestoreAfterEditor)
    }

    private func restoreFocus(_ field: NagareEditorField) {
        Task { @MainActor in
            await Task.yield()
            guard presentedEditor == nil else { return }
            focusedField = field
        }
    }

    @discardableResult
    private func saveDraft() -> Bool {
        guard isDraftStructurallyValid,
              !trimmedTitle.isEmpty else {
            return false
        }

        do {
            let referenceDate = resolvedScheduledDate
            let rule = try recurrence.rule(referenceDate: referenceDate)

            persistedItemID = try dataStore.upsertItem(
                ItemDraft(
                    title: trimmedTitle,
                    notes: savedNotes,
                    scheduledDate: resolvedScheduledDate,
                    includesTime: includesTime,
                    endDate: resolvedEndDate,
                    projectID: selectedProject?.id,
                    recurrenceRule: rule,
                    startTimeSeconds: includesTime
                        ? wallTimeSeconds(resolvedScheduledDate)
                        : nil,
                    endTimeSeconds: resolvedEndDate.map(wallTimeSeconds)
                ),
                existingID: persistedItemID
            )
            return true
        } catch {
            errorMessage = error.localizedDescription
            return false
        }
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
}
