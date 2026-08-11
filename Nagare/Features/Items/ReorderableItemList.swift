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
    let onMoveAcrossDates: ([ItemID], Date, ItemID?) -> Void
    @State private var todoBeingRescheduled: Todo?
    @State private var eventBeingRescheduled: Event?
    @State private var recurrenceTemplateBeingEdited: RecurrenceTemplate?
    @State private var projectMoveTarget: ProjectMoveTarget?

    init(
        groups: [ReorderableItemGroup],
        showsDateHeaders: Bool,
        onOpen: @escaping (Item) -> Void,
        onOpenVirtual: @escaping (VirtualItem) -> Void = { _ in },
        onComplete: @escaping (Todo) -> Void,
        onDelete: @escaping (Item) -> Void,
        onDeleteTemplate: @escaping (RecurrenceTemplate) -> Void = { _ in },
        onMove: @escaping (Date, IndexSet, Int) -> Void,
        onMoveAcrossDates: @escaping ([ItemID], Date, ItemID?) -> Void = {
            _, _, _ in
        }
    ) {
        self.groups = groups
        self.showsDateHeaders = showsDateHeaders
        self.onOpen = onOpen
        self.onOpenVirtual = onOpenVirtual
        self.onComplete = onComplete
        self.onDelete = onDelete
        self.onDeleteTemplate = onDeleteTemplate
        self.onMove = onMove
        self.onMoveAcrossDates = onMoveAcrossDates
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
                .presentationDragIndicator(.visible)
        }
        .sheet(item: $eventBeingRescheduled) { event in
            EventScheduleEditor(event: event)
                .presentationDetents([EventScheduleEditor.sheetDetent])
                .presentationDragIndicator(.visible)
        }
        .sheet(item: $recurrenceTemplateBeingEdited) { template in
            RecurrenceEditor(template: template)
                .presentationDetents([.medium])
                .presentationDragIndicator(.visible)
        }
        .sheet(item: $projectMoveTarget) { target in
            ProjectMoveEditor(target: target)
                .presentationDetents([.fraction(0.25)])
                .presentationDragIndicator(.visible)
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
                onMoveProject: {
                    projectMoveTarget = ProjectMoveTarget($0)
                },
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
                onMoveProject: {
                    projectMoveTarget = .template(item.template)
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
