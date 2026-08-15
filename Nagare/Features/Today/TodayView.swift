import SwiftUI

struct TodayView: View {
    @NagareDataStoreEnvironment private var dataStore

    @State private var errorMessage: String?
    @State private var displayedItemIDs: [ItemID] = []

    let onOpenNotes: (NotesDestination) -> Void

    private var todos: [TodoRecordSnapshot] {
        dataStore.todos
    }

    private var events: [EventRecordSnapshot] {
        dataStore.events
    }

    private var todayTodos: [TodoRecordSnapshot] {
        let calendar = Calendar.autoupdatingCurrent
        guard let tomorrow = calendar.date(byAdding: .day, value: 1, to: calendar.startOfDay(for: .now)) else {
            return todos.filter { $0.completedAt == nil }
        }

        return todos.filter { todo in
            todo.completedAt == nil && todo.scheduledDate < tomorrow
        }
    }

    private var todayEvents: [EventRecordSnapshot] {
        let calendar = Calendar.autoupdatingCurrent
        let today = calendar.startOfDay(for: .now)
        guard let tomorrow = calendar.date(byAdding: .day, value: 1, to: today) else {
            return []
        }

        return events.filter { event in
            event.scheduledDate >= today && event.scheduledDate < tomorrow
        }
    }

    private var persistedTodayItems: [ItemRecordSnapshot] {
        ItemRecordSnapshot.ordered(todos: todayTodos, events: todayEvents)
    }

    private var persistedTodayItemIDs: [ItemID] {
        persistedTodayItems.map(\.id)
    }

    private var todayItems: [ItemRecordSnapshot] {
        guard !displayedItemIDs.isEmpty else {
            return persistedTodayItems
        }

        let itemsByID = Dictionary(
            uniqueKeysWithValues: persistedTodayItems.map { ($0.id, $0) }
        )
        let projectedItems = displayedItemIDs.compactMap { itemsByID[$0] }
        let projectedIDs = Set(projectedItems.map(\.id))
        return projectedItems + persistedTodayItems.filter {
            !projectedIDs.contains($0.id)
        }
    }

    var body: some View {
        Group {
            if todayItems.isEmpty {
                ContentUnavailableView(
                    "Nothing for today",
                    systemImage: "checkmark.circle"
                )
            } else {
                ReorderableItemList(
                    groups: [
                        ReorderableItemGroup(
                            date: Calendar.autoupdatingCurrent.startOfDay(for: .now),
                            items: todayItems
                        )
                    ],
                    showsDateHeaders: false,
                    onOpen: { onOpenNotes(NotesDestination($0)) },
                    onComplete: complete,
                    onDelete: delete,
                    onMove: { _, sourceOffsets, destinationOffset in
                        move(from: sourceOffsets, to: destinationOffset)
                    }
                )
            }
        }
        .onChange(of: persistedTodayItemIDs, initial: true) { _, itemIDs in
            displayedItemIDs = itemIDs
        }
        .overlay(alignment: .topLeading) {
#if DEBUG
            if ProcessInfo.processInfo.arguments.contains("--use-reorder-ui-test-store") {
                Button("Test reorder last before first") {
                    guard
                        let sourceIndex = todayItems.firstIndex(where: {
                            guard case .todo(let todo) = $0 else {
                                return false
                            }
                            return todo.title == "Reorder Third"
                        }),
                        let destinationIndex = todayItems.firstIndex(where: {
                            guard case .todo(let todo) = $0 else {
                                return false
                            }
                            return todo.title == "Reorder First"
                        })
                    else {
                        errorMessage = "Nagare couldn't prepare the reorder regression action. (ORDER-UI-006)"
                        return
                    }
                    move(
                        from: IndexSet(integer: sourceIndex),
                        to: destinationIndex
                    )
                }
                .font(.caption2)
                .accessibilityIdentifier("Test reorder last before first")
            }
#endif
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

    private func complete(_ todo: TodoRecordSnapshot) {
        do {
            try withAnimation {
                try dataStore.completeTodo(todo.id)
            }
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func delete(_ items: [ItemRecordSnapshot]) {
        do {
            try dataStore.deleteItems(items.map(\.id))
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func saveDisplayedOrder() {
        do {
            let plan = try OrderingPlanner.displayedOrder(
                displayedItemIDs,
                contains: persistedTodayItems.map {
                    OrderingPlanner.Entry(id: $0.id, order: $0.order)
                }
            )
            try dataStore.saveItemOrdering(plan.assignments.map {
                ItemOrderingChange(id: $0.id, order: $0.order)
            })
        } catch {
            displayedItemIDs = persistedTodayItemIDs
            errorMessage = error.localizedDescription
        }
    }

    private func move(from sourceOffsets: IndexSet, to destinationOffset: Int) {
        do {
            let newItemIDs = try ReorderProjection.applying(
                sourceOffsets: sourceOffsets,
                toOffset: destinationOffset,
                to: todayItems.map(\.id)
            )
            guard newItemIDs != displayedItemIDs else {
                return
            }
            displayedItemIDs = newItemIDs
            saveDisplayedOrder()
        } catch {
            displayedItemIDs = persistedTodayItemIDs
            errorMessage = error.localizedDescription
        }
    }
}
