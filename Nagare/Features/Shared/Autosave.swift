import SwiftUI

private struct NagareAutosave<Value: Equatable>: ViewModifier {
    @Environment(\.scenePhase) private var scenePhase
    @State private var pendingSave: Task<Void, Never>?

    let value: Value
    let delay: Duration
    let save: () -> Void

    func body(content: Content) -> some View {
        content
            .onChange(of: value) {
                pendingSave?.cancel()
                pendingSave = Task {
                    do { try await Task.sleep(for: delay) }
                    catch { return }
                    save()
                }
            }
            .onDisappear(perform: flush)
            .onChange(of: scenePhase) {
                if scenePhase != .active { flush() }
            }
            .nagareOnAppTermination(flush)
    }

    private func flush() {
        pendingSave?.cancel()
        pendingSave = nil
        save()
    }
}

extension View {
    func nagareAutosave<Value: Equatable>(
        _ value: Value,
        after delay: Duration = .milliseconds(500),
        save: @escaping () -> Void
    ) -> some View {
        modifier(NagareAutosave(value: value, delay: delay, save: save))
    }
}
