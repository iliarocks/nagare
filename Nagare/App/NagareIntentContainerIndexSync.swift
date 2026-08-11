import SwiftUI

private struct NagareIntentContainerIndexSync: ViewModifier {
    let store: NagareIntentStore

    func body(content: Content) -> some View {
        content.task {
            try? await store.refreshIntentContainerIndex()
        }
    }
}

extension View {
    @ViewBuilder
    func syncNagareIntentContainers(
        using store: NagareIntentStore?
    ) -> some View {
        if let store {
            modifier(NagareIntentContainerIndexSync(store: store))
        } else {
            self
        }
    }
}
