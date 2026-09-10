import SwiftUI
#if os(macOS)
import AppKit
#endif

enum NagareListSectionSpacing {
    case standard
    case custom(CGFloat)
}


extension View {
    @ViewBuilder
    func nagareBottomScrollContentMargin(
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
