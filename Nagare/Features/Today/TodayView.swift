import SwiftData
import SwiftUI

struct TodayView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.scenePhase) private var scenePhase

    @Query(sort: \Todo.scheduledDate)
    private var todos: [Todo]

    @State private var isCreatingTodo = false
    @State private var errorMessage: String?

    private var todayTodos: [Todo] {
        let calendar = Calendar.autoupdatingCurrent
        guard let tomorrow = calendar.date(byAdding: .day, value: 1, to: calendar.startOfDay(for: .now)) else {
            return todos.filter { $0.completedAt == nil }
        }

        // Include an unrolled past item while maintenance is completing so it never
        // briefly disappears from Today.
        return todos
            .filter { todo in
                todo.completedAt == nil && todo.scheduledDate < tomorrow
            }
            .sorted { first, second in
                if first.scheduledDate == second.scheduledDate {
                    return first.createdAt < second.createdAt
                }
                return first.scheduledDate < second.scheduledDate
            }
    }

    var body: some View {
        Group {
            if todayTodos.isEmpty {
                ContentUnavailableView(
                    "Nothing for today",
                    systemImage: "checkmark.circle",
                    description: Text("Add a todo when something comes to mind.")
                )
            } else {
                List {
                    ForEach(todayTodos) { todo in
                        TodoRow(todo: todo) {
                            complete(todo)
                        }
                        .swipeActions(edge: .trailing) {
                            Button("Delete", systemImage: "trash", role: .destructive) {
                                delete(todo)
                            }
                        }
                    }
                }
            }
        }
        .navigationTitle("Today")
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button("New Todo", systemImage: "plus") {
                    isCreatingTodo = true
                }
            }
        }
        .sheet(isPresented: $isCreatingTodo) {
            TodoFormView()
        }
        .task {
            rollUnfinishedTodosForward()
        }
        .onChange(of: scenePhase) { _, newPhase in
            if newPhase == .active {
                rollUnfinishedTodosForward()
            }
        }
        .alert("Nagare Couldn't Save", isPresented: isShowingError) {
            Button("OK", role: .cancel) {
                errorMessage = nil
            }
        } message: {
            Text(errorMessage ?? "An unknown error occurred.")
        }
    }

    private var isShowingError: Binding<Bool> {
        Binding(
            get: { errorMessage != nil },
            set: { isPresented in
                if !isPresented {
                    errorMessage = nil
                }
            }
        )
    }

    private func complete(_ todo: Todo) {
        todo.completedAt = .now
        saveChanges()
    }

    private func delete(_ todo: Todo) {
        modelContext.delete(todo)
        saveChanges()
    }

    private func rollUnfinishedTodosForward() {
        do {
            try TodoMaintenance.rollUnfinishedTodosForward(in: modelContext)
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func saveChanges() {
        do {
            try modelContext.save()
        } catch {
            modelContext.rollback()
            errorMessage = error.localizedDescription
        }
    }
}

private struct TodoRow: View {
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

            Text(todo.title)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(.vertical, 4)
    }
}
