import SwiftUI

struct ItemRow: View {
    let item: Item
    let onOpen: (Item) -> Void
    let onComplete: (Todo) -> Void
    let onChangeSchedule: (Item) -> Void
    let onDelete: (Item) -> Void

    var body: some View {
        ZStack {
            switch item {
            case .todo(let todo):
                TodoRow(
                    todo: todo,
                    onOpen: { onOpen(item) },
                    onComplete: { onComplete(todo) },
                    onChangeDate: { onChangeSchedule(item) },
                    onDelete: { onDelete(item) }
                )
            case .event(let event):
                EventRow(
                    event: event,
                    onOpen: { onOpen(item) },
                    onChangeSchedule: { onChangeSchedule(item) },
                    onDelete: { onDelete(item) }
                )
            }
        }
        .swipeActions(edge: .trailing, allowsFullSwipe: true) {
            Button(role: .destructive) {
                onDelete(item)
            } label: {
                Image(systemName: "trash")
            }
            .accessibilityLabel("Delete")
        }
        .swipeActions(edge: .leading, allowsFullSwipe: true) {
            Button {
                onChangeSchedule(item)
            } label: {
                Image(systemName: "calendar")
            }
            .tint(.blue)
            .accessibilityLabel(scheduleActionTitle)
        }
    }

    private var scheduleActionTitle: String {
        switch item {
        case .todo:
            "Change Date"
        case .event:
            "Change Schedule"
        }
    }
}
