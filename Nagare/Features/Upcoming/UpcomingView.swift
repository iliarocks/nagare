import SwiftData
import SwiftUI

struct UpcomingView: View {
    @Environment(\.modelContext) private var modelContext

    @Query(sort: \Todo.scheduledDate)
    private var todos: [Todo]

    @Query(sort: \Event.startDate)
    private var events: [Event]

    @State private var todoBeingRescheduled: Todo?
    @State private var eventBeingRescheduled: Event?
    @State private var notesDestination: NotesDestination?
    @State private var errorMessage: String?

    private var itemGroups: [ItemGroup] {
        let calendar = Calendar.autoupdatingCurrent
        guard let tomorrow = calendar.date(
            byAdding: .day,
            value: 1,
            to: calendar.startOfDay(for: .now)
        ) else {
            return []
        }

        let upcomingTodos = todos.filter { todo in
            todo.completedAt == nil && todo.scheduledDate >= tomorrow
        }

        let upcomingEvents = events.filter { event in
            event.startDate >= tomorrow
        }

        let dates = Set(
            upcomingTodos.map { calendar.startOfDay(for: $0.scheduledDate) }
                + upcomingEvents.map { calendar.startOfDay(for: $0.startDate) }
        )

        return dates.map { date in
            let todosForDate = upcomingTodos.filter {
                calendar.isDate($0.scheduledDate, inSameDayAs: date)
            }
            let eventsForDate = upcomingEvents.filter {
                calendar.isDate($0.startDate, inSameDayAs: date)
            }

            return ItemGroup(
                date: date,
                items: ScheduledItem.ordered(
                    todos: todosForDate,
                    events: eventsForDate
                )
            )
        }
        .sorted { $0.date < $1.date }
    }

    var body: some View {
        Group {
            if itemGroups.isEmpty {
                ContentUnavailableView(
                    "Nothing upcoming",
                    systemImage: "calendar",
                    description: Text("Future todos and events will appear here.")
                )
            } else {
                List {
                    ForEach(itemGroups) { group in
                        Section {
                            ForEach(group.items) { item in
                                switch item {
                                case .todo(let todo):
                                    TodoRow(
                                        todo: todo,
                                        onOpen: { notesDestination = .todo(todo) },
                                        onComplete: { complete(todo) }
                                    )
                                    .swipeActions(edge: .trailing) {
                                        Button(role: .destructive) {
                                            delete(todo)
                                        } label: {
                                            Label("Delete", systemImage: "trash")
                                                .labelStyle(.iconOnly)
                                        }

                                        Button {
                                            todoBeingRescheduled = todo
                                        } label: {
                                            Image(systemName: "calendar")
                                        }
                                        .tint(.blue)
                                    }

                                case .event(let event):
                                    EventRow(
                                        event: event,
                                        onOpen: { notesDestination = .event(event) }
                                    )
                                        .swipeActions(edge: .trailing) {
                                            Button(role: .destructive) {
                                                delete(event)
                                            } label: {
                                                Label("Delete", systemImage: "trash")
                                                    .labelStyle(.iconOnly)
                                            }

                                            Button {
                                                eventBeingRescheduled = event
                                            } label: {
                                                Image(systemName: "calendar")
                                            }
                                            .tint(.blue)
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
        .sheet(item: $todoBeingRescheduled) { todo in
            TodoDateEditor(todo: todo)
                .presentationDetents([.medium])
        }
        .sheet(item: $eventBeingRescheduled) { event in
            EventScheduleEditor(event: event)
                .presentationDetents([.medium])
        }
        .navigationDestination(item: $notesDestination) { destination in
            switch destination {
            case .todo(let todo):
                ItemNotesView(item: todo)
            case .event(let event):
                ItemNotesView(item: event)
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

    private func delete(_ event: Event) {
        modelContext.delete(event)
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

private struct ItemGroup: Identifiable {
    let date: Date
    let items: [ScheduledItem]

    var id: Date { date }
}
