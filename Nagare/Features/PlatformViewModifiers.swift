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

    init(
        _ placeholder: String = "Notes",
        text: Binding<String>,
        accessibilityIdentifier: String,
        focus: FocusState<NagareEditorField?>.Binding? = nil
    ) {
        self.placeholder = placeholder
        _text = text
        self.accessibilityIdentifier = accessibilityIdentifier
        self.focus = focus
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
            .accessibilityIdentifier(accessibilityIdentifier)
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
private struct NagareEscapeKeyMonitor: NSViewRepresentable {
    let action: () -> Void

    func makeCoordinator() -> Coordinator {
        Coordinator(action: action)
    }

    func makeNSView(context: Context) -> NSView {
        context.coordinator.start()
        return NSView(frame: .zero)
    }

    func updateNSView(_ nsView: NSView, context: Context) {
        context.coordinator.action = action
    }

    static func dismantleNSView(_ nsView: NSView, coordinator: Coordinator) {
        coordinator.stop()
    }

    final class Coordinator {
        var action: () -> Void
        private var monitor: Any?

        init(action: @escaping () -> Void) {
            self.action = action
        }

        func start() {
            guard monitor == nil else { return }
            monitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) {
                [weak self] event in
                guard event.keyCode == 53 else { return event }
                self?.action()
                return nil
            }
        }

        func stop() {
            guard let monitor else { return }
            NSEvent.removeMonitor(monitor)
            self.monitor = nil
        }

        deinit {
            stop()
        }
    }
}

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

private struct NagareModalSurface<Presented: View>: View {
    let dismiss: () -> Void
    @ViewBuilder let presented: () -> Presented

    var body: some View {
        ZStack {
            Button(action: dismiss) {
                Color.black.opacity(0.24)
                    .ignoresSafeArea()
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityHidden(true)

            presented()
                .environment(
                    \.nagareDismissModal,
                    NagareModalDismissAction(dismiss)
                )
                .background(
                    .regularMaterial,
                    in: RoundedRectangle(
                        cornerRadius: 18,
                        style: .continuous
                    )
                )
                .clipShape(
                    RoundedRectangle(
                        cornerRadius: 18,
                        style: .continuous
                    )
                )
                .overlay {
                    RoundedRectangle(
                        cornerRadius: 18,
                        style: .continuous
                    )
                    .stroke(.separator.opacity(0.65), lineWidth: 1)
                }
                .shadow(color: .black.opacity(0.35), radius: 24, y: 12)
                .transition(
                    .scale(scale: 0.97).combined(with: .opacity)
                )
        }
        .onExitCommand(perform: dismiss)
        .background(NagareEscapeKeyMonitor(action: dismiss))
        .zIndex(1)
    }
}

private struct NagareItemModalModifier<
    Item: Identifiable,
    Presented: View
>: ViewModifier {
    @Binding var item: Item?
    let onDismiss: () -> Void
    @ViewBuilder let presented: (Item) -> Presented

    func body(content: Content) -> some View {
        content
            .overlay {
                if let item {
                    NagareModalSurface(dismiss: dismiss) {
                        presented(item)
                    }
                }
            }
            .animation(.snappy(duration: 0.18), value: item?.id)
            .onChange(of: item?.id) { oldValue, newValue in
                if oldValue != nil && newValue == nil {
                    onDismiss()
                }
            }
    }

    private func dismiss() {
        item = nil
    }
}

private struct NagarePresentedModalModifier<Presented: View>: ViewModifier {
    @Binding var isPresented: Bool
    let onDismiss: () -> Void
    @ViewBuilder let presented: () -> Presented

    func body(content: Content) -> some View {
        content
            .overlay {
                if isPresented {
                    NagareModalSurface(dismiss: dismiss) {
                        presented()
                    }
                }
            }
            .animation(.snappy(duration: 0.18), value: isPresented)
            .onChange(of: isPresented) { oldValue, newValue in
                if oldValue && !newValue {
                    onDismiss()
                }
            }
    }

    private func dismiss() {
        isPresented = false
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
    func nagareEventTimeFont() -> some View {
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
            .listRowInsets(
                EdgeInsets(top: 0, leading: 8, bottom: 0, trailing: 8)
            )
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
            .padding(.horizontal, 12)
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
#if os(macOS)
        overlay {
            if isPresented.wrappedValue {
                NagareModalSurface(dismiss: {
                    withAnimation(.snappy(duration: 0.18)) {
                        isPresented.wrappedValue = false
                    }
                }) {
                    composer()
                }
            }
        }
#else
        sheet(isPresented: isPresented) {
            composer()
                .nagareSheetDetents([.large])
                .presentationDragIndicator(.visible)
        }
#endif
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
    func nagareComposerContentPadding() -> some View {
#if os(macOS)
        padding(.horizontal, 24)
            .padding(.top, 32)
            .padding(.bottom, 16)
#else
        padding(24)
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
        overlay(alignment: .bottom) {
            Rectangle()
                .fill(.regularMaterial)
                .mask {
                    LinearGradient(
                        colors: [.clear, .black],
                        startPoint: .top,
                        endPoint: .bottom
                    )
                }
                .frame(height: 64)
                .ignoresSafeArea(edges: .bottom)
                .allowsHitTesting(false)
        }
    }

    @ViewBuilder
    func nagareModal<Item: Identifiable, Presented: View>(
        item: Binding<Item?>,
        onDismiss: @escaping () -> Void = {},
        @ViewBuilder content: @escaping (Item) -> Presented
    ) -> some View {
#if os(macOS)
        modifier(
            NagareItemModalModifier(
                item: item,
                onDismiss: onDismiss,
                presented: content
            )
        )
#else
        sheet(item: item, onDismiss: onDismiss) { value in
            content(value)
                .environment(
                    \.nagareDismissModal,
                    NagareModalDismissAction {
                        item.wrappedValue = nil
                    }
                )
        }
#endif
    }

    @ViewBuilder
    func nagareModal<Presented: View>(
        isPresented: Binding<Bool>,
        onDismiss: @escaping () -> Void = {},
        @ViewBuilder content: @escaping () -> Presented
    ) -> some View {
#if os(macOS)
        modifier(
            NagarePresentedModalModifier(
                isPresented: isPresented,
                onDismiss: onDismiss,
                presented: content
            )
        )
#else
        sheet(isPresented: isPresented, onDismiss: onDismiss) {
            content()
                .environment(
                    \.nagareDismissModal,
                    NagareModalDismissAction {
                        isPresented.wrappedValue = false
                    }
                )
        }
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
