import SwiftUI

struct VirtualItemRow: View {
    let item: VirtualItem
    let onOpen: () -> Void
    let onChangeRepeat: () -> Void
    let onDelete: () -> Void

    var body: some View {
        Button(action: onOpen) {
            HStack(spacing: 12) {
                Text(item.template.title)
                    .fixedSize(horizontal: false, vertical: true)
                    .frame(maxWidth: .infinity, alignment: .leading)

                if let startDate = item.startDate {
                    EventTimeLabel(
                        startDate: startDate,
                        endDate: item.endDate
                    )
                }

                Image(systemName: "repeat")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .accessibilityHidden(true)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .padding(.vertical, 4)
        .accessibilityLabel("\(item.template.title), future repeating item")
        .swipeActions(edge: .trailing, allowsFullSwipe: true) {
            Button(role: .destructive, action: onDelete) {
                Image(systemName: "trash")
            }
            .accessibilityLabel("Delete")

            Button(action: onChangeRepeat) {
                Image(systemName: "repeat")
            }
            .tint(.blue)
            .accessibilityLabel("Change Repeat")
        }
    }
}
