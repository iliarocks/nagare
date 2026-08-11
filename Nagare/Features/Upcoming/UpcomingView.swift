import SwiftData
import SwiftUI

struct UpcomingView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.scenePhase) private var scenePhase

    @Query(sort: \Todo.scheduledDate)
    private var todos: [Todo]

    @Query(sort: \Event.scheduledDate)
    private var events: [Event]

    @Query(sort: \RecurrenceTemplate.createdAt)
    private var recurrenceTemplates: [RecurrenceTemplate]

    @State private var errorMessage: String?
    @State private var displayedItemIDsByDate: [Date: [ItemID]] = [:]
    @State private var virtualItems: [VirtualItem] = []

    let onOpenNotes: (NotesDestination) -> Void

    @MainActor
    private var recurrenceProjectionRevisions: [RecurrenceProjectionRevision] {
        recurrenceTemplates.map(RecurrenceProjectionRevision.init)
    }

    private var persistedItemGroups: [ReorderableItemGroup] {
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
            event.scheduledDate >= tomorrow
        }

        let populatedDates = Set(
            upcomingTodos.map { calendar.startOfDay(for: $0.scheduledDate) }
                + upcomingEvents.map { calendar.startOfDay(for: $0.scheduledDate) }
                + virtualItems.map { calendar.startOfDay(for: $0.date) }
        )
        return populatedDates.map { date in
            let todosForDate = upcomingTodos.filter {
                calendar.isDate($0.scheduledDate, inSameDayAs: date)
            }
            let eventsForDate = upcomingEvents.filter {
                calendar.isDate($0.scheduledDate, inSameDayAs: date)
            }
            let virtualItemsForDate = virtualItems.filter {
                calendar.isDate($0.date, inSameDayAs: date)
            }
            .sorted {
                if $0.order != $1.order {
                    return $0.order < $1.order
                }
                return $0.id.templateID.uuidString
                    < $1.id.templateID.uuidString
            }

            return ReorderableItemGroup(
                date: date,
                items: Item.ordered(
                    todos: todosForDate,
                    events: eventsForDate
                ),
                virtualItems: virtualItemsForDate
            )
        }
        .sorted { $0.date < $1.date }
    }

    private var itemGroups: [ReorderableItemGroup] {
        let persistedGroupsByDate = Dictionary(
            uniqueKeysWithValues: persistedItemGroups.map { ($0.date, $0) }
        )
        let itemsByID = Dictionary(
            uniqueKeysWithValues: persistedItemGroups
                .flatMap(\.items)
                .map { ($0.id, $0) }
        )
        let displayedIDSet = Set(displayedItemIDsByDate.values.joined())
        let dates = Set(persistedGroupsByDate.keys)
            .union(displayedItemIDsByDate.keys)

        return dates.sorted().map { date in
            let persistedGroup = persistedGroupsByDate[date]
                ?? ReorderableItemGroup(date: date, items: [])
            guard let displayedIDs = displayedItemIDsByDate[date] else {
                return persistedGroup
            }

            let projectedItems = displayedIDs.compactMap { itemsByID[$0] }
            return ReorderableItemGroup(
                date: date,
                items: projectedItems + persistedGroup.items.filter {
                    !displayedIDSet.contains($0.id)
                },
                virtualItems: persistedGroup.virtualItems
            )
        }
    }

    private var persistedItemIDsByDate: [Date: [ItemID]] {
        Dictionary(
            uniqueKeysWithValues: persistedItemGroups.map {
                ($0.date, $0.items.map(\.id))
            }
        )
    }

    var body: some View {
        Group {
            if itemGroups.isEmpty {
                ContentUnavailableView(
                    "Nothing upcoming",
                    systemImage: "calendar"
                )
            } else {
                ReorderableItemList(
                    groups: itemGroups,
                    showsDateHeaders: true,
                    onOpen: { onOpenNotes(NotesDestination($0)) },
                    onOpenVirtual: {
                        onOpenNotes(.template($0.template))
                    },
                    onComplete: complete,
                    onDelete: delete,
                    onDeleteTemplate: deleteTemplate,
                    onMove: move,
                    onMoveAcrossDates: moveAcrossDates
                )
            }
        }
        .onChange(of: persistedItemIDsByDate, initial: true) { _, itemIDsByDate in
            displayedItemIDsByDate = itemIDsByDate
        }
        .onChange(
            of: recurrenceProjectionRevisions,
            initial: true
        ) {
            refreshVirtualItems()
        }
        .onChange(of: scenePhase) { _, newPhase in
            if newPhase == .active {
                refreshVirtualItems()
            }
        }
        .overlay(alignment: .topLeading) {
#if DEBUG
            if ProcessInfo.processInfo.arguments.contains("--use-reorder-ui-test-store") {
                Button("Test reorder upcoming last before first") {
                    guard let group = itemGroups.first,
                          group.items.count > 1 else {
                        errorMessage = "Nagare couldn't prepare the upcoming reorder regression action. (ORDER-UI-009)"
                        return
                    }
                    move(
                        on: group.date,
                        from: IndexSet(integer: group.items.index(before: group.items.endIndex)),
                        to: group.items.startIndex
                    )
                }
                .font(.caption2)
                .accessibilityIdentifier("Test reorder upcoming last before first")
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

    private func complete(_ todo: Todo) {
        do {
            try withAnimation {
                _ = try RecurrencePersistence.complete(
                    todo,
                    in: modelContext
                )
            }
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func delete(_ item: Item) {
        do {
            switch item {
            case .todo(let todo):
                try RecurrencePersistence.delete(todo, in: modelContext)
            case .event(let event):
                try RecurrencePersistence.delete(event, in: modelContext)
            }
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func deleteTemplate(_ template: RecurrenceTemplate) {
        do {
            try RecurrencePersistence.deleteTemplate(
                template,
                in: modelContext
            )
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func refreshVirtualItems() {
        let calendar = Calendar.autoupdatingCurrent
        let today = calendar.startOfDay(for: .now)
        guard let tomorrow = calendar.date(
            byAdding: .day,
            value: 1,
            to: today
        ),
        let horizon = calendar.date(
            byAdding: .month,
            value: 2,
            to: today
        ) else {
            virtualItems = []
            errorMessage = VirtualItemProjectionError
                .horizonCalculationFailed
                .localizedDescription
            return
        }

        do {
            virtualItems = try VirtualItemProjection.generate(
                from: recurrenceTemplates,
                starting: tomorrow,
                through: horizon,
                calendar: calendar
            )
        } catch {
            virtualItems = []
            errorMessage = error.localizedDescription
        }
    }

    private func move(
        on date: Date,
        from sourceOffsets: IndexSet,
        to destinationOffset: Int
    ) {
        do {
            guard let group = itemGroups.first(where: { $0.date == date }) else {
                throw ReorderProjection.ProjectionError.missingDestination
            }
            let newItemIDs = try ReorderProjection.applying(
                sourceOffsets: sourceOffsets,
                toOffset: destinationOffset,
                to: group.items.map(\.id)
            )
            guard newItemIDs != displayedItemIDsByDate[date] else {
                return
            }

            displayedItemIDsByDate[date] = newItemIDs
            try ItemOrdering.saveDisplayedOrder(
                newItemIDs,
                on: date,
                in: modelContext
            )
        } catch {
            modelContext.rollback()
            displayedItemIDsByDate = persistedItemIDsByDate
            errorMessage = error.localizedDescription
        }
    }

    private func moveAcrossDates(
        _ sourceIDs: [ItemID],
        to destinationDate: Date,
        before destinationID: ItemID?
    ) {
        do {
            let displayedGroups = Dictionary(
                uniqueKeysWithValues: itemGroups.map {
                    ($0.date, $0.items.map(\.id))
                }
            )
            displayedItemIDsByDate = try ReorderProjection.applying(
                sources: sourceIDs,
                to: destinationDate,
                before: destinationID,
                in: displayedGroups
            )
            try ItemOrdering.move(
                sourceIDs,
                to: destinationDate,
                before: destinationID,
                in: modelContext
            )
        } catch {
            modelContext.rollback()
            displayedItemIDsByDate = persistedItemIDsByDate
            errorMessage = error.localizedDescription
        }
    }

}
