import Foundation
import SwiftData

enum ItemOrdering {
    static let spacing: Int64 = 1_024

    @MainActor
    static func nextSortOrder(
        on date: Date,
        in context: ModelContext,
        calendar: Calendar = .autoupdatingCurrent
    ) throws -> Int64 {
        let items = try items(on: date, in: context, calendar: calendar)
        guard let lastOrder = items.last?.sortOrder else {
            return spacing
        }

        let (nextOrder, overflowed) = lastOrder.addingReportingOverflow(spacing)
        if !overflowed {
            return nextOrder
        }

        normalize(items)
        return Int64(items.count + 1) * spacing
    }

    @MainActor
    static func move(
        _ sourceIDs: [ScheduledItemID],
        before destinationID: ScheduledItemID?,
        in items: [ScheduledItem],
        context: ModelContext
    ) throws {
        let sourceIDSet = Set(sourceIDs)
        if let destinationID, sourceIDSet.contains(destinationID) {
            return
        }
        let movingItems = items.filter { sourceIDSet.contains($0.id) }
        guard !movingItems.isEmpty else {
            return
        }

        var reorderedItems = items.filter { !sourceIDSet.contains($0.id) }
        let destinationIndex = destinationID.flatMap { destinationID in
            reorderedItems.firstIndex { $0.id == destinationID }
        } ?? reorderedItems.endIndex
        reorderedItems.insert(contentsOf: movingItems, at: destinationIndex)

        guard reorderedItems.map(\.id) != items.map(\.id) else {
            return
        }

        if movingItems.count == 1,
           let movedIndex = reorderedItems.firstIndex(where: { sourceIDSet.contains($0.id) }),
           let newOrder = order(at: movedIndex, in: reorderedItems) {
            reorderedItems[movedIndex].sortOrder = newOrder
        } else {
            normalize(reorderedItems)
        }

        try context.save()
    }

    @MainActor
    static func items(
        on date: Date,
        in context: ModelContext,
        calendar: Calendar = .autoupdatingCurrent
    ) throws -> [ScheduledItem] {
        let start = calendar.startOfDay(for: date)
        guard let end = calendar.date(byAdding: .day, value: 1, to: start) else {
            return []
        }

        let todoDescriptor = FetchDescriptor<Todo>(
            predicate: #Predicate { todo in
                todo.completedAt == nil
                    && todo.scheduledDate >= start
                    && todo.scheduledDate < end
            }
        )
        let eventDescriptor = FetchDescriptor<Event>(
            predicate: #Predicate { event in
                event.startDate >= start && event.startDate < end
            }
        )

        return ScheduledItem.ordered(
            todos: try context.fetch(todoDescriptor),
            events: try context.fetch(eventDescriptor)
        )
    }

    private static func order(
        at index: Int,
        in items: [ScheduledItem]
    ) -> Int64? {
        let previousOrder = index > items.startIndex ? items[index - 1].sortOrder : nil
        let nextOrder = index + 1 < items.endIndex ? items[index + 1].sortOrder : nil

        switch (previousOrder, nextOrder) {
        case (nil, nil):
            return spacing
        case (nil, let nextOrder?):
            let (order, overflowed) = nextOrder.subtractingReportingOverflow(spacing)
            return overflowed ? nil : order
        case (let previousOrder?, nil):
            let (order, overflowed) = previousOrder.addingReportingOverflow(spacing)
            return overflowed ? nil : order
        case (let previousOrder?, let nextOrder?):
            let (distance, overflowed) = nextOrder.subtractingReportingOverflow(previousOrder)
            guard !overflowed, distance > 1 else {
                return nil
            }
            return previousOrder + distance / 2
        }
    }

    private static func normalize(_ items: [ScheduledItem]) {
        for (index, item) in items.enumerated() {
            item.sortOrder = Int64(index + 1) * spacing
        }
    }
}
