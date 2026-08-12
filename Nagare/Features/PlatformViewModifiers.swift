import AppIntents
import SwiftUI

enum NagareListSectionSpacing {
    case standard
    case custom(CGFloat)
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
    func nagareToolbarIcon() -> some View {
#if os(macOS)
        // The large bordered toolbar style adds six more vertical points than
        // horizontal ones. This content frame produces a square 36-point
        // control, allowing the requested circle border to remain circular.
        frame(width: 24, height: 18)
#else
        self
#endif
    }

    @ViewBuilder
    func nagareToolbarButton() -> some View {
#if os(macOS)
        controlSize(.large)
            .buttonStyle(.bordered)
            .buttonBorderShape(.circle)
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
            .padding(.horizontal, 5)
            .padding(.vertical, 8)
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
    func nagareDetailsForm(
        width: CGFloat = 440,
        height: CGFloat
    ) -> some View {
#if os(macOS)
        formStyle(.grouped)
            .scrollContentBackground(.hidden)
            .padding(16)
            .frame(width: width, height: height)
#else
        self
#endif
    }

    @ViewBuilder
    func nagareDetailsPanel(
        width: CGFloat = 440,
        height: CGFloat
    ) -> some View {
#if os(macOS)
        padding(20)
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
                        .contentShape(Rectangle())
                        .onTapGesture {
                            withAnimation(.snappy(duration: 0.18)) {
                                isPresented.wrappedValue = false
                            }
                        }

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
                .zIndex(1)
            }
        }
#else
        sheet(isPresented: isPresented) {
            composer()
                .presentationDetents([.large])
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
