import SwiftUI

struct TodoRow: View {
    let todo: Todo
    let onComplete: () -> Void

    var body: some View {
        HStack(spacing: 12) {
            Button(action: onComplete) {
                Image(systemName: "circle")
                    .font(.title3)
            }
            .buttonStyle(.plain)
            .foregroundStyle(.secondary)
            .accessibilityLabel("Complete \(todo.title)")

            NavigationLink {
                TodoNotesView(todo: todo)
            } label: {
                Text(todo.title)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
        }
        .padding(.vertical, 4)
    }
}
