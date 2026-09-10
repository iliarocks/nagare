import SwiftUI
#if os(macOS)
import AppKit
#endif

/// The native metadata controls shared by item creation and note editing.
struct NagareEditorMetadataToolbar: ToolbarContent {
    let scheduleTitle: String
    let scheduleAccessibilityIdentifier: String
    let projects: [ProjectRecordSnapshot]
    let selectedProject: ProjectRecordSnapshot?
    let hasRepeat: Bool
    let projectAccessibilityIdentifier: String
    let repeatAccessibilityIdentifier: String
    let submitAccessibilityIdentifier: String?
    let isSubmitDisabled: Bool
    let onSchedule: (() -> Void)?
    let onSelectProject: (ProjectRecordSnapshot?) -> Void
    let onRepeat: (() -> Void)?
    let onSubmit: (() -> Void)?

    var body: some ToolbarContent {
        ToolbarItem(placement: .nagareLeading) {
            NagareEditorScheduleControl(
                title: scheduleTitle,
                accessibilityIdentifier: scheduleAccessibilityIdentifier,
                action: onSchedule
            )
        }

        ToolbarItemGroup(placement: .nagareTrailing) {
            NagareEditorProjectControl(
                projects: projects,
                selectedProject: selectedProject,
                accessibilityIdentifier: projectAccessibilityIdentifier,
                onSelect: onSelectProject
            )

            NagareEditorRepeatControl(
                hasRepeat: hasRepeat,
                accessibilityIdentifier: repeatAccessibilityIdentifier,
                action: onRepeat
            )

            NagareEditorSubmitControl(
                accessibilityIdentifier: submitAccessibilityIdentifier,
                isDisabled: isSubmitDisabled,
                action: onSubmit
            )
        }
    }
}

#if os(macOS)
/// macOS sheets do not host SwiftUI navigation toolbars consistently, so the
/// same controls are placed in a native in-sheet header there.
private struct NagareEditorMetadataHeader: View {
    let scheduleTitle: String
    let scheduleAccessibilityIdentifier: String
    let projects: [ProjectRecordSnapshot]
    let selectedProject: ProjectRecordSnapshot?
    let hasRepeat: Bool
    let projectAccessibilityIdentifier: String
    let repeatAccessibilityIdentifier: String
    let submitAccessibilityIdentifier: String?
    let isSubmitDisabled: Bool
    let onSchedule: (() -> Void)?
    let onSelectProject: (ProjectRecordSnapshot?) -> Void
    let onRepeat: (() -> Void)?
    let onSubmit: (() -> Void)?

    var body: some View {
        HStack(spacing: 8) {
            NagareEditorScheduleControl(
                title: scheduleTitle,
                accessibilityIdentifier: scheduleAccessibilityIdentifier,
                action: onSchedule
            )

            Spacer()

            NagareEditorProjectControl(
                projects: projects,
                selectedProject: selectedProject,
                accessibilityIdentifier: projectAccessibilityIdentifier,
                onSelect: onSelectProject
            )

            NagareEditorRepeatControl(
                hasRepeat: hasRepeat,
                accessibilityIdentifier: repeatAccessibilityIdentifier,
                action: onRepeat
            )

            NagareEditorSubmitControl(
                accessibilityIdentifier: submitAccessibilityIdentifier,
                isDisabled: isSubmitDisabled,
                action: onSubmit
            )
        }
        .controlSize(.large)
        .padding(.horizontal, 16)
        .padding(.top, 12)
        .padding(.bottom, 8)
    }
}
#endif

private struct NagareEditorScheduleControl: View {
    let title: String
    let accessibilityIdentifier: String
    let action: (() -> Void)?

    var body: some View {
        Button {
            action?()
        } label: {
            Text(title)
                .lineLimit(1)
        }
        .disabled(action == nil)
        .accessibilityIdentifier(accessibilityIdentifier)
    }
}

private struct NagareEditorProjectControl: View {
    let projects: [ProjectRecordSnapshot]
    let selectedProject: ProjectRecordSnapshot?
    let accessibilityIdentifier: String
    let onSelect: (ProjectRecordSnapshot?) -> Void

    var body: some View {
        Menu {
            ProjectMenuActions(
                projects: projects,
                selectedProject: selectedProject,
                onSelect: onSelect
            )
        } label: {
            Label("Project", systemImage: "folder")
                .labelStyle(.iconOnly)
                .foregroundStyle(
                    selectedProject == nil ? Color.primary : Color.accentColor
                )
        }
        .menuOrder(.fixed)
        .accessibilityIdentifier(accessibilityIdentifier)
    }
}

private struct NagareEditorRepeatControl: View {
    let hasRepeat: Bool
    let accessibilityIdentifier: String
    let action: (() -> Void)?

    @ViewBuilder
    var body: some View {
        if let action {
            Button(action: action) {
                Label("Repeat", systemImage: "repeat")
                    .labelStyle(.iconOnly)
                    .foregroundStyle(
                        hasRepeat ? Color.accentColor : Color.primary
                    )
            }
            .accessibilityIdentifier(accessibilityIdentifier)
        }
    }
}

private struct NagareEditorSubmitControl: View {
    let accessibilityIdentifier: String?
    let isDisabled: Bool
    let action: (() -> Void)?

    @ViewBuilder
    var body: some View {
        if let action, let accessibilityIdentifier {
            Button(action: action) {
                Label("Submit", systemImage: "checkmark")
                    .labelStyle(.iconOnly)
            }
            .buttonStyle(.borderedProminent)
            .disabled(isDisabled)
            .accessibilityIdentifier(accessibilityIdentifier)
        }
    }
}

#if os(macOS)
private struct NagareProjectCreationHeader: View {
    let isSubmitDisabled: Bool
    let onClose: () -> Void
    let onSubmit: () -> Void

    var body: some View {
        HStack {
            Button(action: onClose) {
                Label("Close", systemImage: "xmark")
                    .labelStyle(.iconOnly)
            }
            .accessibilityIdentifier("Create Project Close")

            Spacer()

            Button(action: onSubmit) {
                Label("Create Project", systemImage: "checkmark")
                    .labelStyle(.iconOnly)
            }
            .buttonStyle(.glassProminent)
            .disabled(isSubmitDisabled)
            .accessibilityIdentifier("Create Project Submit")
        }
        .controlSize(.large)
        .padding(.horizontal, 16)
        .padding(.top, 12)
        .padding(.bottom, 8)
    }
}
#endif

struct NagareProjectCreationToolbar: ToolbarContent {
    let isSubmitDisabled: Bool
    let onClose: () -> Void
    let onSubmit: () -> Void

    var body: some ToolbarContent {
        ToolbarItem(placement: .nagareLeading) {
            Button(action: onClose) {
                Label("Close", systemImage: "xmark")
                    .labelStyle(.iconOnly)
            }
            .accessibilityIdentifier("Create Project Close")
        }

        ToolbarItem(placement: .nagareTrailing) {
            Button(action: onSubmit) {
                Label("Create Project", systemImage: "checkmark")
                    .labelStyle(.iconOnly)
            }
            .buttonStyle(.borderedProminent)
            .disabled(isSubmitDisabled)
            .accessibilityIdentifier("Create Project Submit")
        }
    }
}

enum ScheduleToolbarPresentation {
    static func title(
        scheduledDate: Date,
        includesTime: Bool,
        endDate: Date?
    ) -> String {
        let date = scheduledDate.formatted(
            .dateTime.month(.abbreviated).day()
        )
        guard includesTime else { return date }

        let startTime = scheduledDate.formatted(
            date: .omitted,
            time: .shortened
        )
        guard let endDate else {
            return "\(date)  \(startTime)"
        }

        let endTime = endDate.formatted(
            date: .omitted,
            time: .shortened
        )
        return "\(date)  \(startTime) - \(endTime)"
    }
}


#if os(macOS)
private struct NagareToolbarButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 16))
            .frame(width: 36, height: 36)
            .contentShape(Circle())
            .glassEffect(
                .regular.interactive(),
                in: Circle()
            )
            .opacity(configuration.isPressed ? 0.72 : 1)
    }
}
#endif

extension ToolbarItemPlacement {
    static var nagareLeading: ToolbarItemPlacement {
#if os(macOS)
        .navigation
#else
        .topBarLeading
#endif
    }

    static var nagareTrailing: ToolbarItemPlacement {
#if os(macOS)
        .primaryAction
#else
        .topBarTrailing
#endif
    }
}


extension View {
    @ViewBuilder
    func nagareEditorMetadataChrome(
        scheduleTitle: String,
        scheduleAccessibilityIdentifier: String,
        projects: [ProjectRecordSnapshot],
        selectedProject: ProjectRecordSnapshot?,
        hasRepeat: Bool,
        projectAccessibilityIdentifier: String,
        repeatAccessibilityIdentifier: String,
        submitAccessibilityIdentifier: String? = nil,
        isSubmitDisabled: Bool = false,
        onSchedule: (() -> Void)?,
        onSelectProject: @escaping (ProjectRecordSnapshot?) -> Void,
        onRepeat: (() -> Void)?,
        onSubmit: (() -> Void)? = nil
    ) -> some View {
#if os(macOS)
        safeAreaInset(edge: .top, spacing: 0) {
            NagareEditorMetadataHeader(
                scheduleTitle: scheduleTitle,
                scheduleAccessibilityIdentifier:
                    scheduleAccessibilityIdentifier,
                projects: projects,
                selectedProject: selectedProject,
                hasRepeat: hasRepeat,
                projectAccessibilityIdentifier:
                    projectAccessibilityIdentifier,
                repeatAccessibilityIdentifier:
                    repeatAccessibilityIdentifier,
                submitAccessibilityIdentifier:
                    submitAccessibilityIdentifier,
                isSubmitDisabled: isSubmitDisabled,
                onSchedule: onSchedule,
                onSelectProject: onSelectProject,
                onRepeat: onRepeat,
                onSubmit: onSubmit
            )
        }
#else
        toolbar {
            NagareEditorMetadataToolbar(
                scheduleTitle: scheduleTitle,
                scheduleAccessibilityIdentifier:
                    scheduleAccessibilityIdentifier,
                projects: projects,
                selectedProject: selectedProject,
                hasRepeat: hasRepeat,
                projectAccessibilityIdentifier:
                    projectAccessibilityIdentifier,
                repeatAccessibilityIdentifier:
                    repeatAccessibilityIdentifier,
                submitAccessibilityIdentifier:
                    submitAccessibilityIdentifier,
                isSubmitDisabled: isSubmitDisabled,
                onSchedule: onSchedule,
                onSelectProject: onSelectProject,
                onRepeat: onRepeat,
                onSubmit: onSubmit
            )
        }
#endif
    }

    @ViewBuilder
    func nagareProjectCreationChrome(
        isSubmitDisabled: Bool,
        onClose: @escaping () -> Void,
        onSubmit: @escaping () -> Void
    ) -> some View {
#if os(macOS)
        safeAreaInset(edge: .top, spacing: 0) {
            NagareProjectCreationHeader(
                isSubmitDisabled: isSubmitDisabled,
                onClose: onClose,
                onSubmit: onSubmit
            )
        }
#else
        toolbar {
            NagareProjectCreationToolbar(
                isSubmitDisabled: isSubmitDisabled,
                onClose: onClose,
                onSubmit: onSubmit
            )
        }
#endif
    }

    @ViewBuilder
    func nagareToolbarButton() -> some View {
#if os(macOS)
        buttonStyle(NagareToolbarButtonStyle())
#else
        foregroundStyle(.primary)
#endif
    }

    @ViewBuilder
    func nagareItemTitleFont() -> some View {
#if os(macOS)
        font(.system(size: 16))
#else
        self
#endif
    }

    @ViewBuilder
    func nagareTimeFont() -> some View {
#if os(macOS)
        font(.system(size: 14))
#else
        font(.subheadline)
#endif
    }

    @ViewBuilder
    func nagareMetadataFont() -> some View {
#if os(macOS)
        font(.system(size: 14))
#else
        font(.subheadline)
#endif
    }
}
