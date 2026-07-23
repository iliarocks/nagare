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
    let topContentMargin: CGFloat
    let onOpen: (Item) -> Void
    let onOpenVirtual: (VirtualItem) -> Void
    let onComplete: (Todo) -> Void
    let onMove: (Date, IndexSet, Int) -> Void

    init(
        groups: [ReorderableItemGroup],
        showsDateHeaders: Bool,
        topContentMargin: CGFloat = 0,
        onOpen: @escaping (Item) -> Void,
        onOpenVirtual: @escaping (VirtualItem) -> Void = { _ in },
        onComplete: @escaping (Todo) -> Void,
        onMove: @escaping (Date, IndexSet, Int) -> Void
    ) {
        self.groups = groups
        self.showsDateHeaders = showsDateHeaders
        self.topContentMargin = topContentMargin
        self.onOpen = onOpen
        self.onOpenVirtual = onOpenVirtual
        self.onComplete = onComplete
        self.onMove = onMove
    }

    var body: some View {
        List {
            if showsDateHeaders {
                ForEach(groups) { group in
                    Section {
                        rows(for: group)
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
            } else if let group = groups.first {
                rows(for: group)
            }
        }
        .contentMargins(
            .top,
            topContentMargin,
            for: .scrollContent
        )
        .environment(\.editMode, .constant(.active))
    }

    @ViewBuilder
    private func rows(for group: ReorderableItemGroup) -> some View {
        ForEach(group.items) { item in
            ItemRow(
                item: item,
                onOpen: onOpen,
                onComplete: onComplete
            )
        }
        .onMove { sourceOffsets, destinationOffset in
            onMove(group.date, sourceOffsets, destinationOffset)
        }

        ForEach(group.virtualItems) { item in
            VirtualItemRow(
                item: item,
                onOpen: { onOpenVirtual(item) }
            )
        }
    }
}
