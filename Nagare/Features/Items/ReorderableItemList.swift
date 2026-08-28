import SwiftUI

struct ReorderableItemGroup: Identifiable {
    let date: Date
    let items: [ItemRecordSnapshot]
    let virtualItems: [VirtualItem]

    var id: Date { date }

    init(
        date: Date,
        items: [ItemRecordSnapshot],
        virtualItems: [VirtualItem] = []
    ) {
        self.date = date
        self.items = items
        self.virtualItems = virtualItems
    }
}

struct ReorderableItemList: View {
    let groups: [ReorderableItemGroup]
    let showsDateHeaders: Bool
    @Binding var scrollTargetDate: Date?
    let onOpen: (ItemRecordSnapshot) -> Void
    let onOpenVirtual: (VirtualItem) -> Void
    let onComplete: (TodoRecordSnapshot) -> Void
    let onDelete: ([ItemRecordSnapshot]) -> Void
    let onDeleteTemplate: (RecurrenceTemplateRecordSnapshot) -> Void
    let onMove: (Date, IndexSet, Int) -> Void
    let onMoveAcrossDates: ([ItemID], Date, ItemID?) -> Void
    @State private var todoBeingRescheduled: TodoRecordSnapshot?
    @State private var recurrenceTemplateBeingEdited:
        RecurrenceTemplateRecordSnapshot?
    @State private var selectedItemIDs: Set<ItemID> = []
    @State private var itemSelectionBeingRescheduled: ItemSelectionAction?

    init(
        groups: [ReorderableItemGroup],
        showsDateHeaders: Bool,
        scrollTargetDate: Binding<Date?> = .constant(nil),
        onOpen: @escaping (ItemRecordSnapshot) -> Void,
        onOpenVirtual: @escaping (VirtualItem) -> Void = { _ in },
        onComplete: @escaping (TodoRecordSnapshot) -> Void,
        onDelete: @escaping ([ItemRecordSnapshot]) -> Void,
        onDeleteTemplate: @escaping (
            RecurrenceTemplateRecordSnapshot
        ) -> Void = { _ in },
        onMove: @escaping (Date, IndexSet, Int) -> Void,
        onMoveAcrossDates: @escaping ([ItemID], Date, ItemID?) -> Void = {
            _, _, _ in
        }
    ) {
        self.groups = groups
        self.showsDateHeaders = showsDateHeaders
        _scrollTargetDate = scrollTargetDate
        self.onOpen = onOpen
        self.onOpenVirtual = onOpenVirtual
        self.onComplete = onComplete
        self.onDelete = onDelete
        self.onDeleteTemplate = onDeleteTemplate
        self.onMove = onMove
        self.onMoveAcrossDates = onMoveAcrossDates
    }

    var body: some View {
        itemList
        .nagareListSectionSpacing(
            showsDateHeaders ? .custom(48) : .standard
        )
        .reorderContainer(for: ItemRecordSnapshot.self, in: Date.self) { difference in
            apply(difference)
        }
        .onChange(of: availableItemIDs) {
#if os(macOS)
            selectedItemIDs.formIntersection(availableItemIDs)
#endif
        }
        .nagareModal(item: $itemSelectionBeingRescheduled) { selection in
            ItemDateEditor(items: selection.items)
                .nagareSheetDetents([.medium])
                .presentationDragIndicator(.visible)
        }
        .nagareModal(item: $todoBeingRescheduled) { todo in
            TodoScheduleEditor(todo: todo)
        }
        .nagareModal(item: $recurrenceTemplateBeingEdited) { template in
            RecurrenceEditor(template: template)
                .nagareSheetDetents([.medium])
                .presentationDragIndicator(.visible)
        }
    }

    @ViewBuilder
    private var itemList: some View {
        ScrollViewReader { proxy in
            List {
                listRows
            }
            .onChange(of: scrollTargetDate, initial: true) { _, date in
                scroll(to: date, using: proxy)
            }
            .onChange(of: groups.map(\.date)) {
                scroll(to: scrollTargetDate, using: proxy)
            }
        }
    }

    @ViewBuilder
    private var listRows: some View {
        if showsDateHeaders {
            ForEach(groups) { group in
                Section {
                    rows(for: group)
                } header: {
                    Text(upcomingHeaderTitle(for: group.date))
                    .nagareDateSectionHeader(
                        isFirst: group.id == groups.first?.id
                    )
                    .fontWeight(.regular)
                }
                .id(group.date)
            }
        } else if let group = groups.first {
            rows(for: group)
        }
    }

    private func upcomingHeaderTitle(for date: Date) -> String {
        let weekday = date.formatted(.dateTime.weekday(.abbreviated))
        let monthAndDay = date.formatted(
            .dateTime.month(.abbreviated).day()
        )
        return "\(weekday) \(monthAndDay)"
    }

    private func scroll(to target: Date?, using proxy: ScrollViewProxy) {
        guard let target else { return }
        let calendar = Calendar.autoupdatingCurrent
        guard let group = groups.first(where: {
            calendar.isDate($0.date, inSameDayAs: target)
        }) else {
            return
        }

        Task { @MainActor in
            await Task.yield()
            withAnimation(.snappy) {
                proxy.scrollTo(group.date, anchor: .top)
            }
            scrollTargetDate = nil
        }
    }

    @ViewBuilder
    private func rows(for group: ReorderableItemGroup) -> some View {
        ForEach(group.items) { item in
            ItemRow(
                item: item,
                onOpen: onOpen,
                onToggleSelection: { toggleSelection(of: item.id) },
                onComplete: onComplete,
                contextItems: contextItems(for: item),
                onChangeSchedule: presentScheduleEditor,
                onDelete: onDelete
            )
            .nagareItemListRow()
            .nagareCommandSelection(
                position: selectionPosition(
                    for: item.id,
                    in: group.items
                ),
                toggle: { toggleSelection(of: item.id) }
            )
        }
        .reorderable(collectionID: group.date)
        .nagareDesktopListRow()

        ForEach(group.virtualItems) { item in
            VirtualItemRow(
                item: item,
                onOpen: { onOpenVirtual(item) },
                onChangeRepeat: {
                    recurrenceTemplateBeingEdited = item.template
                },
                onDelete: {
                    onDeleteTemplate(item.template)
                }
            )
            .nagareItemListRow()
        }
        .nagareDesktopListRow()
    }

    private var availableItemIDs: Set<ItemID> {
        Set(groups.flatMap(\.items).map(\.id))
    }

    private func selectionPosition(
        for id: ItemID,
        in items: [ItemRecordSnapshot]
    ) -> NagareSelectionPosition {
        NagareSelectionPosition.resolve(
            id: id,
            orderedIDs: items.map(\.id),
            selectedIDs: selectedItemIDs
        )
    }

    private func toggleSelection(of id: ItemID) {
        if selectedItemIDs.contains(id) {
            selectedItemIDs.remove(id)
        } else {
            selectedItemIDs.insert(id)
        }
    }

    private func contextItems(
        for item: ItemRecordSnapshot
    ) -> [ItemRecordSnapshot] {
#if os(macOS)
        guard selectedItemIDs.count > 1,
              selectedItemIDs.contains(item.id) else {
            return [item]
        }
        return groups.flatMap(\.items).filter {
            selectedItemIDs.contains($0.id)
        }
#else
        return [item]
#endif
    }

    private func presentScheduleEditor(_ items: [ItemRecordSnapshot]) {
        guard items.count == 1, let item = items.first else {
            itemSelectionBeingRescheduled = ItemSelectionAction(items: items)
            return
        }
        todoBeingRescheduled = item
    }

    private func apply(
        _ difference: ReorderDifference<ItemID, Date>
    ) {
        guard !difference.sources.isEmpty else {
            return
        }

        let destinationDate = difference.destination.collectionID
        let destinationID: ItemID?
        switch difference.destination.position {
        case .before(let id):
            guard groups.contains(where: { group in
                group.date == destinationDate
                    && group.items.contains(where: { $0.id == id })
            }) else {
                return
            }
            destinationID = id
        case .end:
            destinationID = nil
        }

        let sourceIDSet = Set(difference.sources)
        let sourceGroups = groups.filter { group in
            group.items.contains(where: { sourceIDSet.contains($0.id) })
        }
        let locatedSourceIDs = sourceGroups.flatMap { group in
            group.items.compactMap { item in
                sourceIDSet.contains(item.id) ? item.id : nil
            }
        }
        guard Set(locatedSourceIDs) == sourceIDSet else {
            return
        }

        guard sourceGroups.allSatisfy({ $0.date == destinationDate }),
              let sourceGroup = sourceGroups.first else {
            onMoveAcrossDates(
                difference.sources,
                destinationDate,
                destinationID
            )
            return
        }

        let sourceOffsets = IndexSet(
            sourceGroup.items.indices.filter {
                sourceIDSet.contains(sourceGroup.items[$0].id)
            }
        )
        let destinationOffset: Int
        if let destinationID {
            guard let index = sourceGroup.items.firstIndex(where: {
                $0.id == destinationID
            }) else {
                return
            }
            destinationOffset = index
        } else {
            destinationOffset = sourceGroup.items.endIndex
        }

        onMove(
            sourceGroup.date,
            sourceOffsets,
            destinationOffset
        )
    }
}
