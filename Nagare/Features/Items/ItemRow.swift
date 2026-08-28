import SwiftUI

struct ItemRow: View {
    let item: ItemRecordSnapshot
    let onOpen: (ItemRecordSnapshot) -> Void
    let onToggleSelection: () -> Void
    let onComplete: (TodoRecordSnapshot) -> Void
    let contextItems: [ItemRecordSnapshot]
    let onChangeSchedule: ([ItemRecordSnapshot]) -> Void
    let onDelete: ([ItemRecordSnapshot]) -> Void

    var body: some View {
        TodoRow(
            todo: item,
            onOpen: { onOpen(item) },
            onToggleSelection: onToggleSelection,
            onComplete: { onComplete(item) },
            onChangeDate: { onChangeSchedule([item]) },
            onDelete: { onDelete([item]) }
        )
        .swipeActions(edge: .trailing, allowsFullSwipe: true) {
            Button(role: .destructive) {
                onDelete([item])
            } label: {
                Image(systemName: "trash")
            }
            .accessibilityLabel("Delete")
        }
        .swipeActions(edge: .leading, allowsFullSwipe: false) {
            Button {
                onChangeSchedule([item])
            } label: {
                Image(systemName: scheduleActionIcon)
            }
            .accessibilityLabel(scheduleActionTitle)

        }
        .nagareDesktopContextMenu {
            Button {
                onChangeSchedule(contextItems)
            } label: {
                Label(contextScheduleActionTitle, systemImage: scheduleActionIcon)
            }

            Divider()

            Button(role: .destructive) {
                onDelete(contextItems)
            } label: {
                Label(contextDeleteActionTitle, systemImage: "trash")
            }
        }
    }

    private var scheduleActionTitle: String {
        "Change Date and Time"
    }

    private var scheduleActionIcon: String {
        "calendar.badge.clock"
    }

    private var contextScheduleActionTitle: String {
        guard contextItems.count > 1 else { return scheduleActionTitle }
        return "Change Date for \(contextItems.count) Items"
    }

    private var contextDeleteActionTitle: String {
        contextItems.count > 1
            ? "Delete \(contextItems.count) Items"
            : "Delete"
    }

}
