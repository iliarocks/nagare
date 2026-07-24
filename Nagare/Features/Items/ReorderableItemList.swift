import SwiftUI

struct ReorderableItemGroup: Identifiable {
    let date: Date
    let items: [Item]
    let virtualItems: [VirtualItem]

    var id: Date { date }

    init(
        date: Date,
        items: [Item],
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
    let onOpen: (Item) -> Void
    let onOpenVirtual: (VirtualItem) -> Void
    let onComplete: (Todo) -> Void
    let onDelete: (Item) -> Void
    let onDeleteTemplate: (RecurrenceTemplate) -> Void
    let onMove: (Date, IndexSet, Int) -> Void
    @State private var todoBeingRescheduled: Todo?
    @State private var eventBeingRescheduled: Event?
    @State private var recurrenceTemplateBeingEdited: RecurrenceTemplate?

    init(
        groups: [ReorderableItemGroup],
        showsDateHeaders: Bool,
        onOpen: @escaping (Item) -> Void,
        onOpenVirtual: @escaping (VirtualItem) -> Void = { _ in },
        onComplete: @escaping (Todo) -> Void,
        onDelete: @escaping (Item) -> Void,
        onDeleteTemplate: @escaping (RecurrenceTemplate) -> Void = { _ in },
        onMove: @escaping (Date, IndexSet, Int) -> Void
    ) {
        self.groups = groups
        self.showsDateHeaders = showsDateHeaders
        self.onOpen = onOpen
        self.onOpenVirtual = onOpenVirtual
        self.onComplete = onComplete
        self.onDelete = onDelete
        self.onDeleteTemplate = onDeleteTemplate
        self.onMove = onMove
    }

    var body: some View {
        List {
            if showsDateHeaders {
                ForEach(groups) { group in
                    Section {
                        rows(for: group)
                    } header: {
                        HStack {
                            Text(
                                group.date,
                                format: .dateTime.weekday(.wide)
                            )

                            Spacer()

                            Text(
                                group.date,
                                format: .dateTime
                                    .month(.wide)
                                    .day()
                            )
                        }
                        .font(.caption)
                        .fontWeight(.regular)
                    }
                }
            } else if let group = groups.first {
                rows(for: group)
            }
        }
        .listSectionSpacing(
            showsDateHeaders ? .custom(48) : .default
        )
        .reorderContainer(for: Item.self, in: Date.self) { difference in
            apply(difference)
        }
        .sheet(item: $todoBeingRescheduled) { todo in
            TodoDateEditor(todo: todo)
                .presentationDetents([.medium])
        }
        .sheet(item: $eventBeingRescheduled) { event in
            EventScheduleEditor(event: event)
                .presentationDetents([.medium])
        }
        .sheet(item: $recurrenceTemplateBeingEdited) { template in
            RecurrenceEditor(template: template)
                .presentationDetents([.medium, .large])
        }
    }

    @ViewBuilder
    private func rows(for group: ReorderableItemGroup) -> some View {
        ForEach(group.items) { item in
            ItemRow(
                item: item,
                onOpen: onOpen,
                onComplete: onComplete,
                onChangeSchedule: presentScheduleEditor,
                onDelete: onDelete
            )
        }
        .reorderable(collectionID: group.date)

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
        }
    }

    private func presentScheduleEditor(_ item: Item) {
        switch item {
        case .todo(let todo):
            todoBeingRescheduled = todo
        case .event(let event):
            eventBeingRescheduled = event
        }
    }

    private func apply(
        _ difference: ReorderDifference<ItemID, Date>
    ) {
        guard difference.sources.count == 1,
              let sourceID = difference.sources.first,
              let sourceGroup = groups.first(where: { group in
                  group.items.contains(where: { $0.id == sourceID })
              }),
              sourceGroup.date == difference.destination.collectionID,
              let sourceIndex = sourceGroup.items.firstIndex(
                  where: { $0.id == sourceID }
              ) else {
            return
        }

        let destinationOffset: Int
        switch difference.destination.position {
        case .before(let destinationID):
            guard let index = sourceGroup.items.firstIndex(
                where: { $0.id == destinationID }
            ) else {
                return
            }
            destinationOffset = index

        case .end:
            destinationOffset = sourceGroup.items.endIndex
        }

        onMove(
            sourceGroup.date,
            IndexSet(integer: sourceIndex),
            destinationOffset
        )
    }
}
