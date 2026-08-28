import SwiftUI

struct VirtualItemRow: View {
    let item: VirtualItem
    let onOpen: () -> Void
    let onChangeRepeat: () -> Void
    let onDelete: () -> Void

    var body: some View {
        NagarePrimaryRowAction(action: onOpen) {
            HStack(spacing: 12) {
                Text(item.template.title)
                    .nagareItemTitleFont()
                    .fixedSize(horizontal: false, vertical: true)
                    .frame(maxWidth: .infinity, alignment: .leading)

                if let startDate = item.startDate {
                    ItemTimeLabel(
                        startDate: startDate,
                        endDate: item.endDate
                    )
                }

                Image(systemName: "repeat")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .accessibilityHidden(true)
            }
        }
        .padding(.vertical, 4)
        .accessibilityLabel("\(item.template.title), future repeating item")
        .swipeActions(edge: .trailing, allowsFullSwipe: true) {
            Button(role: .destructive, action: onDelete) {
                Image(systemName: "trash")
            }
            .accessibilityLabel("Delete")
        }
        .swipeActions(edge: .leading, allowsFullSwipe: false) {
            Button(action: onChangeRepeat) {
                Image(systemName: "repeat")
            }
            .accessibilityLabel("Change Repeat")

        }
        .accessibilityAction(named: "Change Repeat") {
            onChangeRepeat()
        }
        .accessibilityAction(named: "Delete") {
            onDelete()
        }
        .nagareDesktopContextMenu {
            Button(action: onChangeRepeat) {
                Label("Change Repeat", systemImage: "repeat")
            }

            Divider()

            Button(role: .destructive, action: onDelete) {
                Label("Delete", systemImage: "trash")
            }
        }
    }
}
