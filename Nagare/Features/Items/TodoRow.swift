import SwiftUI

struct TodoRow: View {
    let todo: Todo
    let onOpen: () -> Void
    let onComplete: () -> Void

    var body: some View {
        HStack(spacing: 12) {
            Button(action: onOpen) {
                Text(todo.title)
                    .fixedSize(horizontal: false, vertical: true)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)

            Button(action: onComplete) {
                Image(systemName: "circle")
                    .font(.title3)
            }
            .buttonStyle(.plain)
            .foregroundStyle(.secondary)
            .accessibilityLabel("Complete \(todo.title)")
        }
        .padding(.vertical, 4)
    }
}
