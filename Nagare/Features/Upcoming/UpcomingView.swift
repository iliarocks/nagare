import SwiftData
import SwiftUI

struct UpcomingView: View {
    @Environment(\.modelContext) private var modelContext

    @Query(sort: \Todo.scheduledDate)
    private var todos: [Todo]

    @State private var errorMessage: String?

    private var todoGroups: [TodoGroup] {
        let calendar = Calendar.autoupdatingCurrent
        guard let tomorrow = calendar.date(
            byAdding: .day,
            value: 1,
            to: calendar.startOfDay(for: .now)
        ) else {
            return []
        }

        let upcomingTodos = todos
            .filter { todo in
                todo.completedAt == nil && todo.scheduledDate >= tomorrow
            }
            .sorted { first, second in
                if first.scheduledDate == second.scheduledDate {
                    return first.createdAt < second.createdAt
                }
                return first.scheduledDate < second.scheduledDate
            }

        return Dictionary(grouping: upcomingTodos) { todo in
            calendar.startOfDay(for: todo.scheduledDate)
        }
        .map { date, todos in
            TodoGroup(date: date, todos: todos)
        }
        .sorted { $0.date < $1.date }
    }

    var body: some View {
        Group {
            if todoGroups.isEmpty {
                ContentUnavailableView(
                    "Nothing upcoming",
                    systemImage: "calendar",
                    description: Text("Future todos and events will appear here.")
                )
            } else {
                List {
                    ForEach(todoGroups) { group in
                        Section {
                            ForEach(group.todos) { todo in
                                TodoRow(todo: todo) {
                                    complete(todo)
                                }
                                .swipeActions(edge: .trailing) {
                                    Button(role: .destructive) {
                                        delete(todo)
                                    } label: {
                                        Label("Delete", systemImage: "trash")
                                            .labelStyle(.iconOnly)
                                    }
                                }
                            }
                        } header: {
                            Text(
                                group.date,
                                format: .dateTime
                                    .weekday(.wide)
                                    .month(.wide)
                                    .day()
                            )
                        }
                    }
                }
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

    private func saveChanges() {
        do {
            try modelContext.save()
        } catch {
            modelContext.rollback()
            errorMessage = error.localizedDescription
        }
    }
}

private struct TodoGroup: Identifiable {
    let date: Date
    let todos: [Todo]

    var id: Date { date }
}
