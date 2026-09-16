import SwiftUI
#if os(macOS)
import AppKit
#endif

extension View {
    /// Finish pending local edits before macOS exits; quitting doesn't
    /// guarantee that SwiftUI calls onDisappear for every open window.
    @ViewBuilder
    func nagareOnAppTermination(_ action: @escaping () -> Void) -> some View {
#if os(macOS)
        onReceive(
            NotificationCenter.default.publisher(
                for: NSApplication.willTerminateNotification
            )
        ) { _ in
            action()
        }
#else
        self
#endif
    }
}
