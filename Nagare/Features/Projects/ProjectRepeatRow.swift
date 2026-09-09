import SwiftUI

struct ProjectRepeatRow: View {
    let template: RecurrenceTemplateRecordSnapshot
    let onOpen: () -> Void
    let onChangeRepeat: () -> Void
    let onDelete: () -> Void

    var body: some View {
        Button(action: onOpen) {
            HStack(spacing: 12) {
                Text(template.title)
                    .nagareItemTitleFont()
                    .fixedSize(horizontal: false, vertical: true)
                    .frame(maxWidth: .infinity, alignment: .leading)

                Image(systemName: "repeat")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .accessibilityHidden(true)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .padding(.vertical, 4)
        .accessibilityLabel("\(template.title), repeating item")
        .nagareMobileSwipeActions(edge: .trailing, allowsFullSwipe: true) {
            Button(role: .destructive, action: onDelete) {
                Image(systemName: "trash")
            }
            .accessibilityLabel("Stop Repeat")
        }
        .nagareMobileSwipeActions(edge: .leading, allowsFullSwipe: false) {
            Button(action: onChangeRepeat) {
                Image(systemName: "repeat")
            }
            .accessibilityLabel("Change Repeat")

        }
        .accessibilityAction(named: "Change Repeat", onChangeRepeat)
        .accessibilityAction(named: "Stop Repeat", onDelete)
        .nagareItemListRow()
        .nagareDesktopContextMenu {
            Button(action: onChangeRepeat) {
                Label("Change Repeat", systemImage: "repeat")
            }

            Divider()

            Button(role: .destructive, action: onDelete) {
                Label("Stop Repeat", systemImage: "trash")
            }
        }
    }
}
