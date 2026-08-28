import AppIntents
import SwiftUI
#if os(macOS)
import AppKit
#endif

enum NagareListSectionSpacing {
    case standard
    case custom(CGFloat)
}

enum NagareEditorField: Hashable {
    case title
    case notes
}

enum NagareSelectionPosition: Equatable {
    case none
    case single
    case first
    case middle
    case last

    static func resolve<ID: Hashable>(
        id: ID,
        orderedIDs: [ID],
        selectedIDs: Set<ID>
    ) -> Self {
        guard selectedIDs.contains(id),
              let index = orderedIDs.firstIndex(of: id) else {
            return .none
        }
        let hasSelectedBefore = index > orderedIDs.startIndex
            && selectedIDs.contains(orderedIDs[index - 1])
        let hasSelectedAfter = index < orderedIDs.index(before: orderedIDs.endIndex)
            && selectedIDs.contains(orderedIDs[index + 1])

        switch (hasSelectedBefore, hasSelectedAfter) {
        case (false, false): return .single
        case (false, true): return .first
        case (true, true): return .middle
        case (true, false): return .last
        }
    }
}

struct NagareModalDismissAction {
    private let action: () -> Void

    init(_ action: @escaping () -> Void = {}) {
        self.action = action
    }

    func callAsFunction() {
        action()
    }
}

private struct NagareModalDismissKey: EnvironmentKey {
    static let defaultValue = NagareModalDismissAction()
}

extension EnvironmentValues {
    var nagareDismissModal: NagareModalDismissAction {
        get { self[NagareModalDismissKey.self] }
        set { self[NagareModalDismissKey.self] = newValue }
    }
}

struct NagareEditableTitle: View {
    let placeholder: String
    @Binding var text: String

    var body: some View {
#if os(macOS)
        TextField(placeholder, text: $text)
#else
        TextField(placeholder, text: $text, axis: .vertical)
#endif
    }
}

struct NagareDocumentEditor: View {
    let placeholder: String
    @Binding var text: String

    private let accessibilityIdentifier: String
    private let focus: FocusState<NagareEditorField?>.Binding?
    private let bottomScrollContentMargin: CGFloat

    init(
        _ placeholder: String = "Notes",
        text: Binding<String>,
        accessibilityIdentifier: String,
        focus: FocusState<NagareEditorField?>.Binding? = nil,
        bottomScrollContentMargin: CGFloat = 0
    ) {
        self.placeholder = placeholder
        _text = text
        self.accessibilityIdentifier = accessibilityIdentifier
        self.focus = focus
        self.bottomScrollContentMargin = bottomScrollContentMargin
    }

    var body: some View {
        ZStack(alignment: .topLeading) {
            editor

            if text.isEmpty {
                Text(placeholder)
                    .nagareDocumentPlaceholderStyle()
            }
        }
        .padding(.horizontal, -5)
    }

    @ViewBuilder
    private var editor: some View {
        if let focus {
            styledEditor
                .focused(focus, equals: .notes)
        } else {
            styledEditor
        }
    }

    private var styledEditor: some View {
        TextEditor(text: $text)
            .textEditorStyle(.plain)
            .nagareDocumentEditorStyle()
            .nagareBottomScrollContentMargin(bottomScrollContentMargin)
            .accessibilityIdentifier(accessibilityIdentifier)
    }
}

enum NagareDocumentBottomFade {
    static let height: CGFloat = 64
    static let scrollContentMargin: CGFloat = height + 16
}

struct NagareDocumentComposerLayout<Title: View, Document: View>: View {
    let bottomPadding: CGFloat
    @ViewBuilder let title: () -> Title
    @ViewBuilder let document: () -> Document

    init(
        bottomPadding: CGFloat = 16,
        @ViewBuilder title: @escaping () -> Title,
        @ViewBuilder document: @escaping () -> Document
    ) {
        self.bottomPadding = bottomPadding
        self.title = title
        self.document = document
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            title()
                .frame(maxWidth: .infinity, alignment: .leading)

            document()
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .padding(.horizontal, 16)
        .padding(.top, 8)
        .padding(.bottom, bottomPadding)
    }
}

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

struct NagarePrimaryRowAction<Label: View>: View {
    let action: () -> Void
    let commandAction: (() -> Void)?
    private let label: Label

    init(
        action: @escaping () -> Void,
        commandAction: (() -> Void)? = nil,
        @ViewBuilder label: () -> Label
    ) {
        self.action = action
        self.commandAction = commandAction
        self.label = label()
    }

    var body: some View {
#if os(macOS)
        label
            .contentShape(Rectangle())
            .onTapGesture {
                if NSEvent.modifierFlags.contains(.command),
                   let commandAction {
                    commandAction()
                    return
                }
                action()
            }
            .accessibilityAddTraits(.isButton)
            .accessibilityAction(.default, action)
#else
        Button(action: action) {
            label
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
#endif
    }
}

#if os(macOS)
private struct NagareInitialFocusReset: NSViewRepresentable {
    func makeNSView(context: Context) -> ResetView {
        ResetView()
    }

    func updateNSView(_ nsView: ResetView, context: Context) {}

    final class ResetView: NSView {
        private var hasResetFocus = false

        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            guard window != nil, !hasResetFocus else { return }
            hasResetFocus = true
            DispatchQueue.main.async { [weak self] in
                self?.window?.makeFirstResponder(nil)
            }
        }
    }
}
#endif

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
    fileprivate func nagareBottomScrollContentMargin(
        _ margin: CGFloat
    ) -> some View {
#if os(macOS)
        safeAreaInset(edge: .bottom, spacing: 0) {
            Color.clear
                .frame(height: margin)
                .allowsHitTesting(false)
        }
#else
        contentMargins(.bottom, margin, for: .scrollContent)
#endif
    }

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

    @ViewBuilder
    func nagareCompactDatePickerStyle() -> some View {
#if os(macOS)
        datePickerStyle(.field)
            .controlSize(.regular)
            .padding(.vertical, 3)
#else
        self
#endif
    }

    @ViewBuilder
    func nagareDateSectionHeader(isFirst: Bool) -> some View {
#if os(macOS)
        font(.system(size: 13))
            .padding(.top, isFirst ? 0 : 12)
#else
        font(.caption)
#endif
    }

    @ViewBuilder
    func nagareContentSectionHeader() -> some View {
#if os(macOS)
        font(.system(size: 13, weight: .medium))
            .foregroundStyle(.secondary)
            .textCase(nil)
            .padding(.top, 12)
#else
        textCase(nil)
#endif
    }

    @ViewBuilder
    func nagareEditorBodyFont() -> some View {
#if os(macOS)
        font(.system(size: 14))
#else
        font(.body)
#endif
    }

    @ViewBuilder
    func nagareDocumentEditorStyle() -> some View {
        scrollContentBackground(.hidden)
            .nagareEditorBodyFont()
    }

    @ViewBuilder
    func nagareDocumentPlaceholderStyle() -> some View {
        nagareEditorBodyFont()
            .foregroundStyle(.tertiary)
#if os(macOS)
            .padding(.horizontal, 5)
#else
            .padding(.horizontal, 5)
            .padding(.vertical, 8)
#endif
            .allowsHitTesting(false)
    }

    @ViewBuilder
    func nagareDesktopListRow() -> some View {
#if os(macOS)
        listRowSeparator(.hidden)
            .listRowBackground(Color.clear)
            .listRowInsets(EdgeInsets())
#else
        self
#endif
    }

    /// The single outer contract for every item-like list row. Keeping the
    /// hit target, visual inset, and minimum height together prevents row
    /// families from drifting apart as their inner content evolves.
    @ViewBuilder
    func nagareItemListRow() -> some View {
#if os(macOS)
        frame(maxWidth: .infinity, alignment: .leading)
            .contentShape(Rectangle())
            .padding(.horizontal, 8)
            .padding(.vertical, 7)
            .frame(minHeight: 40)
#else
        self
#endif
    }

    @ViewBuilder
    func nagareCommandSelection(
        position: NagareSelectionPosition,
        toggle: @escaping () -> Void
    ) -> some View {
#if os(macOS)
        background {
                if position != .none {
                    UnevenRoundedRectangle(
                        topLeadingRadius: position == .single
                            || position == .first ? 8 : 0,
                        bottomLeadingRadius: position == .single
                            || position == .last ? 8 : 0,
                        bottomTrailingRadius: position == .single
                            || position == .last ? 8 : 0,
                        topTrailingRadius: position == .single
                            || position == .first ? 8 : 0,
                        style: .continuous
                    )
                    .fill(Color.primary.opacity(0.1))
                    .padding(
                        .top,
                        position == .middle || position == .last ? -7 : 0
                    )
                    .padding(
                        .bottom,
                        position == .first || position == .middle ? -7 : 0
                    )
                }
            }
            .accessibilityValue(position == .none ? "" : "Selected")
            .accessibilityAction(named: "Toggle Selection", toggle)
#else
        self
#endif
    }

    @ViewBuilder
    func nagareDetailsForm(
        width: CGFloat = 440,
        height: CGFloat
    ) -> some View {
#if os(macOS)
        formStyle(.grouped)
            .scrollContentBackground(.hidden)
            .controlSize(.regular)
            .font(.body)
            .padding(16)
            .frame(width: width, height: height)
#else
        self
#endif
    }

    @ViewBuilder
    func nagareDesktopContextMenu<MenuItems: View>(
        @ViewBuilder menuItems: () -> MenuItems
    ) -> some View {
#if os(macOS)
        contextMenu(menuItems: menuItems)
#else
        self
#endif
    }

    @ViewBuilder
    func nagareDraftComposer<Composer: View>(
        isPresented: Binding<Bool>,
        @ViewBuilder composer: @escaping () -> Composer
    ) -> some View {
        sheet(isPresented: isPresented) {
            composer()
                .nagareNativeSheetMargins()
                .nagareSheetDetents([.large])
                .presentationDragIndicator(.visible)
        }
    }

    @ViewBuilder
    func nagareComposerFrame(
        width: CGFloat,
        height: CGFloat
    ) -> some View {
#if os(macOS)
        frame(width: width, height: height)
#else
        self
#endif
    }

    @ViewBuilder
    func nagareDocumentSheetFrame() -> some View {
#if os(macOS)
        frame(width: 620, height: 400)
#else
        self
#endif
    }

    @ViewBuilder
    func nagareAvoidsInitialFocus() -> some View {
#if os(macOS)
        background(NagareInitialFocusReset())
#else
        self
#endif
    }

    func nagareDocumentBottomFade() -> some View {
        ignoresSafeArea(edges: .bottom)
            .mask {
                VStack(spacing: 0) {
                    Color.black

                    LinearGradient(
                        colors: [.black, .clear],
                        startPoint: .top,
                        endPoint: .bottom
                    )
                    .frame(height: NagareDocumentBottomFade.height)
                }
            }
    }

    @ViewBuilder
    func nagareModal<Item: Identifiable, Presented: View>(
        item: Binding<Item?>,
        onDismiss: @escaping () -> Void = {},
        @ViewBuilder content: @escaping (Item) -> Presented
    ) -> some View {
        sheet(item: item, onDismiss: onDismiss) { value in
            content(value)
                .nagareNativeSheetMargins()
                .environment(
                    \.nagareDismissModal,
                    NagareModalDismissAction {
                        item.wrappedValue = nil
                    }
                )
        }
    }

    @ViewBuilder
    func nagareModal<Presented: View>(
        isPresented: Binding<Bool>,
        onDismiss: @escaping () -> Void = {},
        @ViewBuilder content: @escaping () -> Presented
    ) -> some View {
        sheet(isPresented: isPresented, onDismiss: onDismiss) {
            content()
                .nagareNativeSheetMargins()
                .environment(
                    \.nagareDismissModal,
                    NagareModalDismissAction {
                        isPresented.wrappedValue = false
                    }
                )
        }
    }

    @ViewBuilder
    private func nagareNativeSheetMargins() -> some View {
#if os(macOS)
        padding(8)
#else
        self
#endif
    }

    @ViewBuilder
    func nagareSheetDetents(
        _ detents: Set<PresentationDetent>
    ) -> some View {
#if os(macOS)
        self
#else
        presentationDetents(detents)
#endif
    }

    @ViewBuilder
    func nagareSheetDetents(
        _ detents: Set<PresentationDetent>,
        selection: Binding<PresentationDetent>
    ) -> some View {
#if os(macOS)
        self
#else
        presentationDetents(detents, selection: selection)
#endif
    }

    @ViewBuilder
    func nagareOnOpenIntent(
        perform action: @escaping (OpenNagareIntent) -> Void
    ) -> some View {
#if os(macOS)
        self
#else
        onAppIntentExecution(OpenNagareIntent.self, perform: action)
#endif
    }

    @ViewBuilder
    func nagareListSectionSpacing(
        _ spacing: NagareListSectionSpacing
    ) -> some View {
#if os(macOS)
        self
#else
        switch spacing {
        case .standard:
            listSectionSpacing(.default)
        case .custom(let value):
            listSectionSpacing(.custom(value))
        }
#endif
    }

    @ViewBuilder
    func nagareInlineNavigationTitle() -> some View {
#if os(macOS)
        self
#else
        navigationBarTitleDisplayMode(.inline)
#endif
    }

    @ViewBuilder
    func nagareProjectNavigationTitle(_ title: String) -> some View {
#if os(macOS)
        self
#else
        navigationTitle("")
#endif
    }
}
