import SwiftUI

struct ProjectRepeatRow: View {
    let template: RecurrenceTemplate
    let onOpen: () -> Void
    let onChangeRepeat: () -> Void
    let onMoveProject: () -> Void
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
        .swipeActions(edge: .trailing, allowsFullSwipe: true) {
            Button(role: .destructive, action: onDelete) {
                Image(systemName: "trash")
            }
            .accessibilityLabel("Stop Repeat")
        }
        .swipeActions(edge: .leading, allowsFullSwipe: false) {
            Button(action: onChangeRepeat) {
                Image(systemName: "repeat")
            }
            .tint(.blue)
            .accessibilityLabel("Change Repeat")

            Button(action: onMoveProject) {
                Image(systemName: "folder")
            }
            .tint(.indigo)
            .accessibilityLabel("Move Project")
        }
        .accessibilityAction(named: "Change Repeat", onChangeRepeat)
        .accessibilityAction(named: "Move Project", onMoveProject)
        .accessibilityAction(named: "Stop Repeat", onDelete)
        .nagareDesktopContextMenu {
            Button(action: onChangeRepeat) {
                Label("Change Repeat", systemImage: "repeat")
            }

            Button(action: onMoveProject) {
                Label("Move Project", systemImage: "folder")
            }

            Divider()

            Button(role: .destructive, action: onDelete) {
                Label("Stop Repeat", systemImage: "trash")
            }
        }
    }
}
