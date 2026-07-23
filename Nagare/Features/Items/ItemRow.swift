import SwiftUI

struct ItemRow: View {
    let item: Item
    let onOpen: (Item) -> Void
    let onComplete: (Todo) -> Void

    var body: some View {
        Group {
            switch item {
            case .todo(let todo):
                TodoRow(
                    todo: todo,
                    onOpen: { onOpen(item) },
                    onComplete: { onComplete(todo) }
                )
            case .event(let event):
                EventRow(event: event, onOpen: { onOpen(item) })
            }
        }
    }
}
