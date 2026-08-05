import SwiftUI

struct ProjectRepeatRow: View {
    let template: RecurrenceTemplate
    let onOpen: () -> Void
    let onChangeRepeat: () -> Void
    let onDelete: () -> Void

    var body: some View {
        Button(action: onOpen) {
            HStack(spacing: 12) {
                Text(template.title)
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
        .swipeActions(edge: .trailing, allowsFullSwipe: true) {
            Button(role: .destructive, action: onDelete) {
                Image(systemName: "trash")
            }
            .accessibilityLabel("Stop Repeat")
        }
        .swipeActions(edge: .leading, allowsFullSwipe: true) {
            Button(action: onChangeRepeat) {
                Image(systemName: "repeat")
            }
            .tint(.blue)
            .accessibilityLabel("Change Repeat")
        }
    }
}
