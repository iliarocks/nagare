import Foundation
import SwiftData

enum ItemOrdering {
    enum MoveError: LocalizedError {
        case duplicateSource
        case missingSource
        case missingDestination
        case destinationIsMovingItem
        case invalidOrderKey
        case invalidResult
        case saveFailed(String)

        var code: String {
            switch self {
            case .duplicateSource: "ORDER-001"
            case .missingSource: "ORDER-002"
            case .missingDestination: "ORDER-003"
            case .destinationIsMovingItem: "ORDER-004"
            case .invalidOrderKey: "ORDER-005"
            case .invalidResult: "ORDER-006"
            case .saveFailed: "ORDER-007"
            }
        }

        var errorDescription: String? {
            switch self {
            case .duplicateSource:
                "Nagare couldn't save this order because the move contained the same item more than once. (\(code))"
            case .missingSource:
                "Nagare couldn't save this order because an item being moved could not be found. (\(code))"
            case .missingDestination:
                "Nagare couldn't save this order because the drop position could not be found. (\(code))"
            case .destinationIsMovingItem:
                "Nagare received an unexpected drop position and restored the previous order. (\(code))"
            case .invalidOrderKey:
                "Nagare found an invalid saved position and restored the previous order. (\(code))"
            case .invalidResult:
                "Nagare couldn't verify the new order and restored the previous order. (\(code))"
            case .saveFailed(let message):
                "Nagare couldn't write the new order. \(message) (\(code))"
            }
        }
    }

    enum MoveOutcome: Equatable {
        case noChange
        case saved
    }

    @MainActor
    static func nextOrder(in context: ModelContext) throws -> String {
        let items = try allItems(in: context)

        if let order = FractionalIndex.between(items.last?.order, nil) {
            return order
        }

        try rebalance(items)
        return FractionalIndex.between(items.last?.order, nil) ?? "i"
    }

    @MainActor
    @discardableResult
    static func move(
        _ sourceIDs: [ItemID],
        to destinationDate: Date,
        before destinationID: ItemID?,
        in context: ModelContext,
        calendar: Calendar = .autoupdatingCurrent
    ) throws -> MoveOutcome {
        let allItems = try allItems(in: context)
        let sourceIDSet = Set(sourceIDs)
        guard sourceIDSet.count == sourceIDs.count else {
            throw MoveError.duplicateSource
        }

        let itemsByID = Dictionary(uniqueKeysWithValues: allItems.map { ($0.id, $0) })
        let movingItems = try sourceIDs.map { sourceID in
            guard let item = itemsByID[sourceID] else {
                throw MoveError.missingSource
            }
            return item
        }
        guard movingItems.count == sourceIDs.count else {
            throw MoveError.missingSource
        }

        let destinationDay = calendar.startOfDay(for: destinationDate)
        let destinationItems = allItems.filter {
            calendar.isDate($0.scheduledDate, inSameDayAs: destinationDay)
                && !$0.isCompleted
        }
        let remainingItems = destinationItems.filter { !sourceIDSet.contains($0.id) }

        guard (destinationItems + movingItems).allSatisfy({
            FractionalIndex.isValid($0.order)
        }) else {
            throw MoveError.invalidOrderKey
        }

        if let destinationID, sourceIDSet.contains(destinationID) {
            throw MoveError.destinationIsMovingItem
        }

        let insertionIndex: Int
        switch destinationID {
        case .some(let destinationID):
            guard let index = remainingItems.firstIndex(where: { $0.id == destinationID }) else {
                throw MoveError.missingDestination
            }
            insertionIndex = index
        case nil:
            insertionIndex = remainingItems.endIndex
        }

        var expectedItems = remainingItems
        expectedItems.insert(contentsOf: movingItems, at: insertionIndex)

        if expectedItems.map(\.id) == destinationItems.map(\.id),
           movingItems.allSatisfy({
               calendar.isDate($0.scheduledDate, inSameDayAs: destinationDay)
           }) {
            return .noChange
        }

        let previousOrder = insertionIndex > remainingItems.startIndex
            ? remainingItems[insertionIndex - 1].order
            : nil
        let nextOrder = insertionIndex < remainingItems.endIndex
            ? remainingItems[insertionIndex].order
            : nil

        if let keys = FractionalIndex.between(
            count: movingItems.count,
            previousOrder,
            nextOrder
        ) {
            for (item, key) in zip(movingItems, keys) {
                item.applyOrder(key)
            }
        } else {
            try rebalance(expectedItems)
        }

        for item in movingItems {
            item.move(to: destinationDay, calendar: calendar)
        }

        let actualItems = Item.ordered(allItems.filter {
            calendar.isDate($0.scheduledDate, inSameDayAs: destinationDay)
                && !$0.isCompleted
        })
        guard actualItems.map(\.id) == expectedItems.map(\.id),
              hasStrictlyIncreasingValidOrders(actualItems) else {
            throw MoveError.invalidResult
        }

        do {
            try context.save()
        } catch {
            throw MoveError.saveFailed(error.localizedDescription)
        }
        return .saved
    }

    @MainActor
    static func saveDisplayedOrder(
        _ itemIDs: [ItemID],
        on date: Date,
        in context: ModelContext,
        calendar: Calendar = .autoupdatingCurrent
    ) throws {
        guard Set(itemIDs).count == itemIDs.count else {
            throw MoveError.duplicateSource
        }

        let day = calendar.startOfDay(for: date)
        let allItems = try allItems(in: context)
        let items = allItems.filter {
            calendar.isDate($0.scheduledDate, inSameDayAs: day)
                && !$0.isCompleted
        }
        let itemsByID = Dictionary(uniqueKeysWithValues: items.map { ($0.id, $0) })
        guard itemIDs.count == items.count,
              Set(itemIDs) == Set(items.map(\.id)) else {
            throw MoveError.invalidResult
        }

        let orderedItems = try itemIDs.map { itemID in
            guard let item = itemsByID[itemID] else {
                throw MoveError.missingSource
            }
            return item
        }
        try rebalance(orderedItems)
        guard hasStrictlyIncreasingValidOrders(orderedItems) else {
            throw MoveError.invalidResult
        }

        do {
            try context.save()
        } catch {
            throw MoveError.saveFailed(error.localizedDescription)
        }
    }

    @MainActor
    private static func allItems(in context: ModelContext) throws -> [Item] {
        Item.ordered(
            todos: try context.fetch(FetchDescriptor<Todo>()),
            events: try context.fetch(FetchDescriptor<Event>())
        )
    }

    private static func rebalance(_ items: [Item]) throws {
        let keys = FractionalIndex.rebalancedKeys(count: items.count)
        guard keys.count == items.count else {
            throw MoveError.invalidResult
        }

        for (item, key) in zip(items, keys) {
            item.applyOrder(key)
        }
    }

    private static func hasStrictlyIncreasingValidOrders(_ items: [Item]) -> Bool {
        guard items.allSatisfy({ FractionalIndex.isValid($0.order) }) else {
            return false
        }

        return zip(items, items.dropFirst()).allSatisfy { previous, next in
            previous.order < next.order
        }
    }
}
