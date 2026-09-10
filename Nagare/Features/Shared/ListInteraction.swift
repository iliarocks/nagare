import SwiftUI
#if os(macOS)
import AppKit
#endif

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

#if os(macOS)
private struct NagareSelectionPositionKey: EnvironmentKey {
    static let defaultValue = NagareSelectionPosition.none
}

private extension EnvironmentValues {
    var nagareSelectionPosition: NagareSelectionPosition {
        get { self[NagareSelectionPositionKey.self] }
        set { self[NagareSelectionPositionKey.self] = newValue }
    }
}

private struct NagareSelectionBackground: View {
    let position: NagareSelectionPosition

    var body: some View {
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
            .padding(.top, position == .middle || position == .last ? -7 : 0)
            .padding(.bottom, position == .first || position == .middle ? -7 : 0)
        }
    }
}

private struct NagareDesktopContextMenu<MenuItems: View>: ViewModifier {
    @Environment(\.nagareSelectionPosition) private var selectionPosition
    @State private var isPresented = false
    let menuItems: MenuItems

    func body(content: Content) -> some View {
        content
            .background {
                // Existing selections already supply the grouped highlight.
                if isPresented && selectionPosition == .none {
                    NagareSelectionBackground(position: .single)
                }
            }
            .overlay {
                NagareContextMenuTarget(
                    menuItems: menuItems,
                    isPresented: $isPresented
                )
                .accessibilityHidden(true)
            }
    }
}

/// Present a native menu without SwiftUI's contextual row outline. Only
/// secondary clicks are intercepted; row clicks, controls, and drags pass through.
private struct NagareContextMenuTarget<MenuItems: View>: NSViewRepresentable {
    let menuItems: MenuItems
    @Binding var isPresented: Bool

    func makeNSView(context: Context) -> MenuTargetView {
        MenuTargetView()
    }

    func updateNSView(_ nsView: MenuTargetView, context: Context) {
        nsView.presentMenu = { [weak nsView] event in
            isPresented = true
            // Allow the SwiftUI highlight to render before menu tracking starts.
            DispatchQueue.main.async {
                defer { isPresented = false }
                guard let nsView, nsView.window != nil else { return }
                let menu = NSHostingMenu(rootView: menuItems)
                NSMenu.popUpContextMenu(menu, with: event, for: nsView)
            }
        }
    }

    final class MenuTargetView: NSView {
        var presentMenu: ((NSEvent) -> Void)?

        override func hitTest(_ point: NSPoint) -> NSView? {
            guard let event = NSApp.currentEvent,
                  event.type == .rightMouseDown
                    || (event.type == .leftMouseDown
                        && event.modifierFlags.contains(.control)) else {
                return nil
            }
            return super.hitTest(point)
        }

        override func rightMouseDown(with event: NSEvent) {
            presentMenu?(event)
        }

        override func mouseDown(with event: NSEvent) {
            presentMenu?(event)
        }
    }
}
#endif

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

extension View {
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

    @ViewBuilder
    func nagareDesktopItemListRows() -> some View {
#if os(macOS)
        listRowSeparator(.hidden)
            .listRowBackground(Color.clear)
            .listRowInsets(
                EdgeInsets(
                    top: 0,
                    leading: -8,
                    bottom: 0,
                    trailing: -8
                )
            )
#else
        self
#endif
    }

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
                NagareSelectionBackground(position: position)
            }
            .environment(\.nagareSelectionPosition, position)
            .accessibilityValue(position == .none ? "" : "Selected")
            .accessibilityAction(named: "Toggle Selection", toggle)
#else
        self
#endif
    }

    @ViewBuilder
    func nagareDesktopContextMenu<MenuItems: View>(
        @ViewBuilder menuItems: () -> MenuItems
    ) -> some View {
#if os(macOS)
        modifier(NagareDesktopContextMenu(menuItems: menuItems()))
#else
        self
#endif
    }

    @ViewBuilder
    func nagareMobileSwipeActions<Actions: View>(
        edge: HorizontalEdge,
        allowsFullSwipe: Bool,
        @ViewBuilder content: () -> Actions
    ) -> some View {
#if os(iOS)
        swipeActions(edge: edge, allowsFullSwipe: allowsFullSwipe, content: content)
#else
        self
#endif
    }
}
