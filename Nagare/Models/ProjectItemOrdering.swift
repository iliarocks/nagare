import Foundation
import SwiftData

enum ProjectItemOrdering {
    enum OrderingError: LocalizedError {
        case duplicateSource
        case missingSource
        case missingDestination
        case destinationIsMovingItem
        case invalidOrderKey
        case invalidResult
        case saveFailed(String)

        var errorDescription: String? {
            switch self {
            case .duplicateSource:
                "Nagare couldn't move that project item because it appeared more than once. (PROJECT-ITEM-ORDER-001)"
            case .missingSource:
                "Nagare couldn't find a project item being moved. (PROJECT-ITEM-ORDER-002)"
            case .missingDestination:
                "Nagare couldn't find the project item drop position. (PROJECT-ITEM-ORDER-003)"
            case .destinationIsMovingItem:
                "Nagare received an invalid project item drop position. (PROJECT-ITEM-ORDER-004)"
            case .invalidOrderKey:
                "Nagare found an invalid saved project item position. (PROJECT-ITEM-ORDER-005)"
            case .invalidResult:
                "Nagare couldn't verify the new project item order. (PROJECT-ITEM-ORDER-006)"
            case .saveFailed(let message):
                "Nagare couldn't save the project item order. \(message) (PROJECT-ITEM-ORDER-007)"
            }
        }
    }

    @MainActor
    static func nextOrder(
        in project: Project,
        context: ModelContext
    ) throws -> String {
        let items = try activeItems(in: project, context: context)
        if items.allSatisfy({
            $0.projectOrder.map(FractionalIndex.isValid) ?? false
        }),
        let order = FractionalIndex.between(items.last?.projectOrder, nil) {
            return order
        }
        try rebalance(items)
        return FractionalIndex.between(items.last?.projectOrder, nil) ?? "i"
    }

    @MainActor
    static func move(
        _ sourceIDs: [ItemID],
        before destinationID: ItemID?,
        in project: Project,
        context: ModelContext
    ) throws {
        let currentItems = try activeItems(in: project, context: context)
        let sourceIDSet = Set(sourceIDs)
        guard sourceIDSet.count == sourceIDs.count else {
            throw OrderingError.duplicateSource
        }
        let itemsByID = Dictionary(
            uniqueKeysWithValues: currentItems.map { ($0.id, $0) }
        )
        let movingItems = try sourceIDs.map { id in
            guard let item = itemsByID[id] else {
                throw OrderingError.missingSource
            }
            return item
        }
        if let destinationID, sourceIDSet.contains(destinationID) {
            throw OrderingError.destinationIsMovingItem
        }
        guard currentItems.allSatisfy({
            $0.projectOrder.map(FractionalIndex.isValid) ?? false
        }) else {
            throw OrderingError.invalidOrderKey
        }

        let remainingItems = currentItems.filter {
            !sourceIDSet.contains($0.id)
        }
        let insertionIndex: Int
        if let destinationID {
            guard let index = remainingItems.firstIndex(where: {
                $0.id == destinationID
            }) else {
                throw OrderingError.missingDestination
            }
            insertionIndex = index
        } else {
            insertionIndex = remainingItems.endIndex
        }

        var expectedItems = remainingItems
        expectedItems.insert(contentsOf: movingItems, at: insertionIndex)
        if expectedItems.map(\.id) == currentItems.map(\.id) {
            return
        }

        let previousOrder = insertionIndex > remainingItems.startIndex
            ? remainingItems[insertionIndex - 1].projectOrder
            : nil
        let nextOrder = insertionIndex < remainingItems.endIndex
            ? remainingItems[insertionIndex].projectOrder
            : nil
        if let keys = FractionalIndex.between(
            count: movingItems.count,
            previousOrder,
            nextOrder
        ) {
            for (item, key) in zip(movingItems, keys) {
                item.applyProjectOrder(key)
            }
        } else {
            try rebalance(expectedItems)
        }

        let actualItems = try activeItems(in: project, context: context)
        guard actualItems.map(\.id) == expectedItems.map(\.id),
              hasStrictlyIncreasingValidOrders(actualItems) else {
            throw OrderingError.invalidResult
        }

        do {
            try context.save()
        } catch {
            throw OrderingError.saveFailed(error.localizedDescription)
        }
    }

    @MainActor
    private static func activeItems(
        in project: Project,
        context: ModelContext
    ) throws -> [Item] {
        let todos = try context.fetch(FetchDescriptor<Todo>()).filter {
            $0.project?.id == project.id && $0.completedAt == nil
        }
        let events = try context.fetch(FetchDescriptor<Event>()).filter {
            $0.project?.id == project.id
        }
        return Item.orderedInProject(todos: todos, events: events)
    }

    private static func rebalance(_ items: [Item]) throws {
        let keys = FractionalIndex.rebalancedKeys(count: items.count)
        guard keys.count == items.count else {
            throw OrderingError.invalidResult
        }
        for (item, key) in zip(items, keys) {
            item.applyProjectOrder(key)
        }
    }

    private static func hasStrictlyIncreasingValidOrders(
        _ items: [Item]
    ) -> Bool {
        let orders = items.compactMap(\.projectOrder)
        guard orders.count == items.count,
              orders.allSatisfy(FractionalIndex.isValid) else {
            return false
        }
        return zip(orders, orders.dropFirst()).allSatisfy(<)
    }
}
