import SwiftUI

struct TodoRow: View {
    let todo: TodoRecordSnapshot
    let onOpen: () -> Void
    let onComplete: () -> Void
    let onChangeDate: () -> Void
    let onMoveProject: () -> Void
    let onDelete: () -> Void
    @State private var isCompleting = false

    var body: some View {
        HStack(spacing: 12) {
            NagarePrimaryRowAction(action: onOpen) {
                Text(todo.title)
                    .nagareItemTitleFont()
                    .fixedSize(horizontal: false, vertical: true)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            .accessibilityAction(named: "Change Date", onChangeDate)
            .accessibilityAction(named: "Move Project", onMoveProject)
            .accessibilityAction(named: "Delete", onDelete)

            Button(action: complete) {
                Image(
                    systemName: isCompleting
                        ? "checkmark.circle.fill"
                        : "circle"
                )
                    .font(.title3)
                    .contentTransition(.symbolEffect(.replace))
            }
            .buttonStyle(.plain)
            .foregroundStyle(
                isCompleting ? Color.accentColor : Color.secondary
            )
            .disabled(isCompleting)
            .accessibilityLabel("Complete \(todo.title)")
        }
        .padding(.vertical, 4)
    }

    private func complete() {
        withAnimation(.snappy(duration: 0.2)) {
            isCompleting = true
        }

        Task {
            do {
                try await Task.sleep(for: .milliseconds(300))
            } catch {
                return
            }

            onComplete()

            if todo.completedAt == nil {
                withAnimation(.snappy(duration: 0.2)) {
                    isCompleting = false
                }
            }
        }
    }
}
