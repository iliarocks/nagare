import SwiftUI

struct NagareCommandActions {
    let createItem: () -> Void
    let showCompleted: () -> Void
}

private struct NagareCommandActionsKey: FocusedValueKey {
    typealias Value = NagareCommandActions
}

extension FocusedValues {
    var nagareCommandActions: NagareCommandActions? {
        get { self[NagareCommandActionsKey.self] }
        set { self[NagareCommandActionsKey.self] = newValue }
    }
}

#if os(macOS)
struct NagareCommands: Commands {
    @FocusedValue(\.nagareCommandActions) private var actions

    var body: some Commands {
        CommandGroup(replacing: .newItem) {
            Button("New Item") {
                actions?.createItem()
            }
            .keyboardShortcut("n", modifiers: .command)
            .disabled(actions == nil)
        }

        CommandMenu("Nagare") {
            Button("Show Completed") {
                actions?.showCompleted()
            }
            .keyboardShortcut("h", modifiers: [.command, .shift])
            .disabled(actions == nil)
        }
    }
}
#endif
