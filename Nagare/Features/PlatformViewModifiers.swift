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
        }
        .buttonStyle(.plain)
#endif
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
    func nagareToolbarButton() -> some View {
#if os(macOS)
        buttonStyle(NagareToolbarButtonStyle())
#else
        self
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
#else
        self
#endif
    }

    @ViewBuilder
    func nagareReorderHitTarget() -> some View {
#if os(macOS)
        frame(maxWidth: .infinity, alignment: .leading)
            .contentShape(Rectangle())
#else
        self
#endif
    }

    @ViewBuilder
    func nagareCommandSelection(
        isSelected: Bool,
        toggle: @escaping () -> Void
    ) -> some View {
#if os(macOS)
        background {
            if isSelected {
                RoundedRectangle(cornerRadius: 6, style: .continuous)
                    .fill(Color.accentColor.opacity(0.18))
            }
        }
        .accessibilityValue(isSelected ? "Selected" : "")
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
                ZStack {
                    Color.black.opacity(0.2)
                        .ignoresSafeArea()

                    composer()
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
                .onExitCommand {
                    withAnimation(.snappy(duration: 0.18)) {
                        isPresented.wrappedValue = false
                    }
                }
                .zIndex(1)
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
