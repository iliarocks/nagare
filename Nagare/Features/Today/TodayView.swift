import SwiftData
import SwiftUI

struct TodayView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.scenePhase) private var scenePhase

    @Query(sort: \Todo.scheduledDate)
    private var todos: [Todo]

    @Query(sort: \Event.scheduledDate)
    private var events: [Event]

    @State private var errorMessage: String?
    @State private var displayedItemIDs: [ItemID] = []

    let onOpenNotes: (NotesDestination) -> Void

    private var todayTodos: [Todo] {
        let calendar = Calendar.autoupdatingCurrent
        guard let tomorrow = calendar.date(byAdding: .day, value: 1, to: calendar.startOfDay(for: .now)) else {
            return todos.filter { $0.completedAt == nil }
        }

        return todos.filter { todo in
            todo.completedAt == nil && todo.scheduledDate < tomorrow
        }
    }

    private var todayEvents: [Event] {
        let calendar = Calendar.autoupdatingCurrent
        let today = calendar.startOfDay(for: .now)
        guard let tomorrow = calendar.date(byAdding: .day, value: 1, to: today) else {
            return []
        }

        return events.filter { event in
            event.scheduledDate >= today && event.scheduledDate < tomorrow
        }
    }

    private var persistedTodayItems: [Item] {
        Item.ordered(todos: todayTodos, events: todayEvents)
    }

    private var persistedTodayItemIDs: [ItemID] {
        persistedTodayItems.map(\.id)
    }

    private var todayItems: [Item] {
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
                    systemImage: "checkmark.circle",
                    description: Text("Add an item when something comes to mind.")
                )
            } else {
                GeometryReader { proxy in
                    ReorderableItemList(
                        groups: [
                            ReorderableItemGroup(
                                date: Calendar.autoupdatingCurrent.startOfDay(for: .now),
                                items: todayItems
                            )
                        ],
                        showsDateHeaders: false,
                        topContentMargin: centeredTopMargin(for: proxy.size.height),
                        onOpen: { onOpenNotes(NotesDestination($0)) },
                        onComplete: complete,
                        onMove: { _, sourceOffsets, destinationOffset in
                            move(from: sourceOffsets, to: destinationOffset)
                        }
                    )
                }
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
        .onChange(of: persistedTodayItemIDs, initial: true) { _, itemIDs in
            displayedItemIDs = itemIDs
        }
        .overlay(alignment: .topLeading) {
#if DEBUG
            if ProcessInfo.processInfo.arguments.contains("--use-reorder-ui-test-store") {
                Button("Test reorder last before first") {
                    guard todayItems.count > 1 else {
                        errorMessage = "Nagare couldn't prepare the reorder regression action. (ORDER-UI-006)"
                        return
                    }
                    move(
                        from: IndexSet(integer: todayItems.index(before: todayItems.endIndex)),
                        to: todayItems.startIndex
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

    private func centeredTopMargin(for availableHeight: CGFloat) -> CGFloat {
        let estimatedRowHeight: CGFloat = 52
        let itemsHeight = CGFloat(todayItems.count) * estimatedRowHeight
        return max(0, (availableHeight - itemsHeight) / 2)
    }

    private func complete(_ todo: Todo) {
        todo.completedAt = .now
        saveChanges()
    }

    private func saveDisplayedOrder() {
        do {
            let today = Calendar.autoupdatingCurrent.startOfDay(for: .now)
            try ItemOrdering.saveDisplayedOrder(
                displayedItemIDs,
                on: today,
                in: modelContext
            )
        } catch {
            modelContext.rollback()
            displayedItemIDs = persistedTodayItemIDs
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
