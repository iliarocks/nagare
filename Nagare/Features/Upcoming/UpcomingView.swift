import SwiftData
import SwiftUI

struct UpcomingView: View {
    private struct PresentedFailure: Identifiable {
        let id = UUID()
        let title: String
        let message: String
    }

    @Environment(\.modelContext) private var modelContext
    @Environment(\.scenePhase) private var scenePhase

    @Query(sort: \Todo.scheduledDate)
    private var todos: [Todo]

    @Query(sort: \Event.scheduledDate)
    private var events: [Event]

    @Query(sort: \RecurrenceTemplate.createdAt)
    private var recurrenceTemplates: [RecurrenceTemplate]

    @State private var presentedFailure: PresentedFailure?
    @State private var displayedItemIDsByDate: [Date: [ItemID]] = [:]
    @State private var virtualItems: [VirtualItem] = []

    let onOpenNotes: (NotesDestination) -> Void

    @MainActor
    private var recurrenceProjectionInput: RecurrenceProjectionInput {
        VirtualItemProjection.input(
            templates: recurrenceTemplates,
            todos: todos,
            events: events
        )
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
            of: recurrenceProjectionInput,
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
                        presentSaveFailure(
                            message: "Nagare couldn't prepare the upcoming reorder regression action. (ORDER-UI-009)"
                        )
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
        .alert(item: $presentedFailure) { failure in
            Alert(
                title: Text(failure.title),
                message: Text(failure.message),
                dismissButton: .default(Text("OK"))
            )
        }
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
            presentSaveFailure(error)
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
            presentSaveFailure(error)
        }
    }

    private func deleteTemplate(_ template: RecurrenceTemplate) {
        do {
            try RecurrencePersistence.deleteTemplate(
                template,
                in: modelContext
            )
        } catch {
            presentSaveFailure(error)
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
            presentProjectionFailure(
                UpcomingProjectionError
                .horizonCalculationFailed
            )
            return
        }

        let result = VirtualItemProjection.generate(
            from: recurrenceProjectionInput,
            templates: recurrenceTemplates,
            starting: tomorrow,
            through: horizon,
            calendar: calendar
        )
        virtualItems = result.items
        if let invalidIssue = result.issues.first(where: {
            !$0.isPendingImport
        }) {
            presentProjectionFailure(
                UpcomingProjectionError.invalidTemplate(invalidIssue)
            )
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
            presentSaveFailure(error)
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
            presentSaveFailure(error)
        }
    }

    private func presentSaveFailure(_ error: Error) {
        presentSaveFailure(message: error.localizedDescription)
    }

    private func presentSaveFailure(message: String) {
        presentedFailure = PresentedFailure(
            title: "Nagare Couldn't Save",
            message: message
        )
    }

    private func presentProjectionFailure(_ error: Error) {
        presentedFailure = PresentedFailure(
            title: "Nagare Couldn't Update Upcoming",
            message: error.localizedDescription
        )
    }

}
