import SwiftUI

struct VirtualItemRow: View {
    let item: VirtualItem
    let onOpen: () -> Void

    var body: some View {
        Button(action: onOpen) {
            HStack(spacing: 12) {
                Text(item.template.title)
                    .lineLimit(1)
                    .frame(maxWidth: .infinity, alignment: .leading)

                if let startDate = item.startDate {
                    HStack(spacing: 4) {
                        Text(startDate, format: .dateTime.hour().minute())
                        if let endDate = item.endDate {
                            Text("–")
                            Text(endDate, format: .dateTime.hour().minute())
                        }
                    }
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .fixedSize()
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
    }
}
