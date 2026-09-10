import SwiftUI
#if os(macOS)
import AppKit
#endif

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


extension View {
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
    func nagareNativeSheetMargins() -> some View {
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
}
