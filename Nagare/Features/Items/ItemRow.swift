import SwiftUI

struct ItemRow: View {
    let item: ItemRecordSnapshot
    let onOpen: (ItemRecordSnapshot) -> Void
    let onToggleSelection: () -> Void
    let onComplete: (TodoRecordSnapshot) -> Void
    let contextItems: [ItemRecordSnapshot]
    let onChangeSchedule: ([ItemRecordSnapshot]) -> Void
    let onMoveProject: ([ItemRecordSnapshot]) -> Void
    let onDelete: ([ItemRecordSnapshot]) -> Void

    var body: some View {
        ZStack {
            switch item {
            case .todo(let todo):
                TodoRow(
                    todo: todo,
                    onOpen: { onOpen(item) },
                    onToggleSelection: onToggleSelection,
                    onComplete: { onComplete(todo) },
                    onChangeDate: { onChangeSchedule([item]) },
                    onMoveProject: { onMoveProject([item]) },
                    onDelete: { onDelete([item]) }
                )
            case .event(let event):
                EventRow(
                    event: event,
                    onOpen: { onOpen(item) },
                    onToggleSelection: onToggleSelection,
                    onChangeSchedule: { onChangeSchedule([item]) },
                    onMoveProject: { onMoveProject([item]) },
                    onDelete: { onDelete([item]) }
                )
            }
        }
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
            .tint(.blue)
            .accessibilityLabel(scheduleActionTitle)

            Button {
                onMoveProject([item])
            } label: {
                Image(systemName: "folder")
            }
            .tint(.indigo)
            .accessibilityLabel("Move Project")

        }
        .nagareDesktopContextMenu {
            Button {
                onChangeSchedule(contextItems)
            } label: {
                Label(contextScheduleActionTitle, systemImage: scheduleActionIcon)
            }

            Button {
                onMoveProject(contextItems)
            } label: {
                Label(contextMoveActionTitle, systemImage: "folder")
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
        switch item {
        case .todo: "Change Date"
        case .event: "Change Date and Time"
        }
    }

    private var scheduleActionIcon: String {
        switch item {
        case .todo: "calendar"
        case .event: "calendar.badge.clock"
        }
    }

    private var contextScheduleActionTitle: String {
        guard contextItems.count > 1 else { return scheduleActionTitle }
        return "Change Date for \(contextItems.count) Items"
    }

    private var contextMoveActionTitle: String {
        contextItems.count > 1
            ? "Move \(contextItems.count) Items to Project"
            : "Move Project"
    }

    private var contextDeleteActionTitle: String {
        contextItems.count > 1
            ? "Delete \(contextItems.count) Items"
            : "Delete"
    }

}
