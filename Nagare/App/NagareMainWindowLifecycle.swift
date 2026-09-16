#if os(macOS)
import AppKit
import SwiftUI

/// Only the main window owns the application's lifetime. Supporting windows
/// can close independently, and never keep the app running after it closes.
struct NagareMainWindowLifecycle: NSViewRepresentable {
    func makeNSView(context: Context) -> CloseObserverView {
        CloseObserverView()
    }

    func updateNSView(_ nsView: CloseObserverView, context: Context) {}

    final class CloseObserverView: NSView {
        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            NotificationCenter.default.removeObserver(
                self,
                name: NSWindow.willCloseNotification,
                object: nil
            )
            guard let window else { return }
            NotificationCenter.default.addObserver(
                self,
                selector: #selector(mainWindowWillClose),
                name: NSWindow.willCloseNotification,
                object: window
            )
        }

        @objc private func mainWindowWillClose(_ notification: Notification) {
            // Use normal app termination so pending edits receive the
            // willTerminate notification before the window is dismantled.
            NSApplication.shared.terminate(nil)
        }

        deinit {
            NotificationCenter.default.removeObserver(self)
        }
    }
}
#endif
