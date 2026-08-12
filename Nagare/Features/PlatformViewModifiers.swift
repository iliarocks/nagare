import AppIntents
import SwiftUI

enum NagareListSectionSpacing {
    case standard
    case custom(CGFloat)
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
        navigationTitle(title)
#else
        navigationTitle("")
#endif
    }
}
