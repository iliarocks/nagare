import SwiftData
import SwiftUI

struct TodayView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.scenePhase) private var scenePhase

    @Query(sort: \Todo.scheduledDate)
    private var todos: [Todo]

    @Query(sort: \Event.startDate)
    private var events: [Event]

    @State private var todoBeingRescheduled: Todo?
    @State private var eventBeingRescheduled: Event?
    @State private var notesDestination: NotesDestination?
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

    private var todayEvents: [Event] {
        let calendar = Calendar.autoupdatingCurrent
        let today = calendar.startOfDay(for: .now)
        guard let tomorrow = calendar.date(byAdding: .day, value: 1, to: today) else {
            return []
        }

        return events.filter { event in
            event.startDate >= today && event.startDate < tomorrow
        }
    }

    private var todayItems: [ScheduledItem] {
        ScheduledItem.ordered(todos: todayTodos, events: todayEvents)
    }

    var body: some View {
        Group {
            if todayTodos.isEmpty && todayEvents.isEmpty {
                ContentUnavailableView(
                    "Nothing for today",
                    systemImage: "checkmark.circle",
                    description: Text("Add an item when something comes to mind.")
                )
            } else {
                List {
                    ForEach(todayItems) { item in
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
                    .reorderable()
                }
                .reorderContainer(for: ScheduledItem.self, move: reorder)
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
        .task {
            performMaintenance()
        }
        .onChange(of: scenePhase) { _, newPhase in
            if newPhase == .active {
                performMaintenance()
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

    private func reorder(
        _ difference: ReorderDifference<
            ScheduledItemID,
            ReorderableSingleCollectionIdentifier
        >
    ) {
        let destinationID: ScheduledItemID?
        switch difference.destination.position {
        case .before(let itemID):
            destinationID = itemID
        case .end:
            destinationID = nil
        }

        do {
            try ItemOrdering.move(
                difference.sources,
                before: destinationID,
                in: todayItems,
                context: modelContext
            )
        } catch {
            modelContext.rollback()
            errorMessage = error.localizedDescription
        }
    }

    private func performMaintenance() {
        do {
            try TodoMaintenance.rollUnfinishedTodosForward(in: modelContext)
            try EventMaintenance.deletePastEvents(in: modelContext)
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
