import SwiftUI

struct UpcomingView: View {
    private struct PresentedFailure: Identifiable {
        let id = UUID()
        let title: String
        let message: String
    }

    @NagareDataStoreEnvironment private var dataStore

    @State private var presentedFailure: PresentedFailure?
    @State private var displayedItemIDsByDate: [Date: [ItemID]] = [:]
    @State private var virtualItems: [VirtualItem] = []

    let calendarDay: NagareCalendarDay
    let onOpenNotes: (NotesDestination) -> Void

    private var todos: [TodoRecordSnapshot] {
        dataStore.todos
    }

    private var recurrenceTemplates: [RecurrenceTemplateRecordSnapshot] {
        dataStore.recurrenceTemplates
    }

    @MainActor
    private var recurrenceProjectionInput: RecurrenceProjectionInput {
        dataStore.snapshot.recurrenceProjectionInput
    }

    private var persistedItemGroups: [ReorderableItemGroup] {
        let calendar = calendarDay.calendar
        guard let tomorrow = calendarDay.nextStart else {
            return []
        }

        let upcomingTodos = todos.filter { todo in
            todo.completedAt == nil && todo.scheduledDate >= tomorrow
        }

        let todosByDate = Dictionary(grouping: upcomingTodos) {
            calendar.startOfDay(for: $0.scheduledDate)
        }
        let virtualItemsByDate = Dictionary(grouping: virtualItems.filter { $0.date >= tomorrow }) {
            calendar.startOfDay(for: $0.date)
        }
        let populatedDates = Set(todosByDate.keys).union(virtualItemsByDate.keys)
        return populatedDates.sorted().map { date in
            let virtualItemsForDate = (virtualItemsByDate[date] ?? []).sorted {
                if $0.order != $1.order {
                    return $0.order < $1.order
                }
                return $0.id.templateID.uuidString
                    < $1.id.templateID.uuidString
            }

            return ReorderableItemGroup(
                date: date,
                items: TodoRecordSnapshot.ordered(todosByDate[date] ?? []),
                virtualItems: virtualItemsForDate
            )
        }
    }

    private var itemGroups: [ReorderableItemGroup] {
        let persistedGroups = persistedItemGroups
        let persistedGroupsByDate = Dictionary(
            uniqueKeysWithValues: persistedGroups.map { ($0.date, $0) }
        )
        let itemsByID = Dictionary(
            uniqueKeysWithValues: persistedGroups
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
        let groups = itemGroups
        Group {
            if groups.isEmpty {
                ContentUnavailableView(
                    "Nothing upcoming",
                    systemImage: "calendar"
                )
            } else {
                ReorderableItemList(
                    groups: groups,
                    showsDateHeaders: true,
                    onOpen: { onOpenNotes(NotesDestination($0)) },
                    onOpenVirtual: {
                        onOpenNotes(NotesDestination($0))
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
        .onChange(of: calendarDay) {
            refreshVirtualItems()
        }
        .overlay(alignment: .topLeading) {
#if DEBUG
            if ProcessInfo.processInfo.arguments.contains("--use-reorder-ui-test-store") {
                Button("Test reorder upcoming last before first") {
                    guard let group = groups.first,
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

    private func complete(_ todo: TodoRecordSnapshot) {
        do {
            try withAnimation {
                try dataStore.completeTodo(todo.id)
            }
        } catch {
            presentSaveFailure(error)
        }
    }

    private func delete(_ items: [ItemRecordSnapshot]) {
        do {
            try dataStore.deleteItems(items.map(\.id))
        } catch {
            presentSaveFailure(error)
        }
    }

    private func deleteTemplate(
        _ template: RecurrenceTemplateRecordSnapshot
    ) {
        do {
            try dataStore.deleteRecurrenceTemplate(template.id)
        } catch {
            presentSaveFailure(error)
        }
    }

    private func refreshVirtualItems() {
        let calendar = calendarDay.calendar
        guard let tomorrow = calendarDay.nextStart,
        let horizon = calendar.date(
            byAdding: .month,
            value: 2,
            to: calendarDay.start
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
            let plan = try OrderingPlanner.displayedOrder(
                newItemIDs,
                contains: group.items.map {
                    OrderingPlanner.Entry(id: $0.id, order: $0.order)
                }
            )
            try dataStore.saveItemOrdering(plan.assignments.map {
                ItemOrderingChange(id: $0.id, order: $0.order)
            })
        } catch {
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
            try dataStore.moveItems(
                sourceIDs,
                to: destinationDate,
                before: destinationID
            )
        } catch {
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
