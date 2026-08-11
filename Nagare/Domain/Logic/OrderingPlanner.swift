import Foundation

/// Pure fractional-order planning shared by items, projects, and project items.
/// The planner never reads a database and never mutates one of its inputs.
nonisolated enum OrderingPlanner {
    enum PlanningError: Error, Equatable, Sendable {
        case duplicateSource
        case missingSource
        case missingDestination
        case destinationIsMovingValue
        case invalidOrderKey
        case invalidResult
    }

    struct Entry<ID: Hashable & Sendable>: Equatable, Sendable {
        let id: ID
        let order: String
    }

    struct Assignment<ID: Hashable & Sendable>: Equatable, Sendable {
        let id: ID
        let order: String
    }

    struct Plan<ID: Hashable & Sendable>: Equatable, Sendable {
        let orderedIDs: [ID]
        let assignments: [Assignment<ID>]
    }

    struct NextOrderPlan<ID: Hashable & Sendable>: Equatable, Sendable {
        let order: String
        let repairs: [Assignment<ID>]
    }

    static func nextOrder<ID: Hashable & Sendable>(
        after orderedEntries: [Entry<ID>]
    ) throws -> NextOrderPlan<ID> {
        if orderedEntries.allSatisfy({ FractionalIndex.isValid($0.order) }),
           let order = FractionalIndex.between(
               orderedEntries.last?.order,
               nil
           ) {
            return NextOrderPlan(order: order, repairs: [])
        }

        let repairs = try rebalancedAssignments(
            for: orderedEntries.map(\.id)
        )
        guard let order = FractionalIndex.between(
            repairs.last?.order,
            nil
        ) else {
            throw PlanningError.invalidResult
        }
        return NextOrderPlan(order: order, repairs: repairs)
    }

    static func move<ID: Hashable & Sendable>(
        _ sourceIDs: [ID],
        before destinationID: ID?,
        in orderedDestination: [Entry<ID>],
        sourceEntries: [Entry<ID>],
        validatesSourceOrders: Bool = true
    ) throws -> Plan<ID> {
        let sourceIDSet = Set(sourceIDs)
        guard sourceIDSet.count == sourceIDs.count else {
            throw PlanningError.duplicateSource
        }

        let sourceEntryIDs = Set(sourceEntries.map(\.id))
        guard sourceEntryIDs.count == sourceEntries.count,
              sourceIDs.allSatisfy(sourceEntryIDs.contains) else {
            throw PlanningError.missingSource
        }
        if let destinationID, sourceIDSet.contains(destinationID) {
            throw PlanningError.destinationIsMovingValue
        }
        guard orderedDestination.allSatisfy({
            FractionalIndex.isValid($0.order)
        }),
        !validatesSourceOrders || sourceEntries.allSatisfy({
            FractionalIndex.isValid($0.order)
        }) else {
            throw PlanningError.invalidOrderKey
        }

        let remaining = orderedDestination.filter {
            !sourceIDSet.contains($0.id)
        }
        let insertionIndex: Int
        if let destinationID {
            guard let index = remaining.firstIndex(where: {
                $0.id == destinationID
            }) else {
                throw PlanningError.missingDestination
            }
            insertionIndex = index
        } else {
            insertionIndex = remaining.endIndex
        }

        var expectedIDs = remaining.map(\.id)
        expectedIDs.insert(contentsOf: sourceIDs, at: insertionIndex)

        let previousOrder = insertionIndex > remaining.startIndex
            ? remaining[insertionIndex - 1].order
            : nil
        let nextOrder = insertionIndex < remaining.endIndex
            ? remaining[insertionIndex].order
            : nil

        let assignments: [Assignment<ID>]
        if let keys = FractionalIndex.between(
            count: sourceIDs.count,
            previousOrder,
            nextOrder
        ) {
            assignments = zip(sourceIDs, keys).map {
                Assignment(id: $0.0, order: $0.1)
            }
        } else {
            assignments = try rebalancedAssignments(for: expectedIDs)
        }

        try validate(assignments, expectedIDs: expectedIDs)
        return Plan(orderedIDs: expectedIDs, assignments: assignments)
    }

    static func displayedOrder<ID: Hashable & Sendable>(
        _ displayedIDs: [ID],
        contains entries: [Entry<ID>]
    ) throws -> Plan<ID> {
        guard Set(displayedIDs).count == displayedIDs.count else {
            throw PlanningError.duplicateSource
        }
        guard displayedIDs.count == entries.count,
              Set(displayedIDs) == Set(entries.map(\.id)) else {
            throw PlanningError.invalidResult
        }

        let assignments = try rebalancedAssignments(for: displayedIDs)
        try validate(assignments, expectedIDs: displayedIDs)
        return Plan(orderedIDs: displayedIDs, assignments: assignments)
    }

    private static func rebalancedAssignments<ID: Hashable & Sendable>(
        for ids: [ID]
    ) throws -> [Assignment<ID>] {
        let keys = FractionalIndex.rebalancedKeys(count: ids.count)
        guard keys.count == ids.count else {
            throw PlanningError.invalidResult
        }
        return zip(ids, keys).map {
            Assignment(id: $0.0, order: $0.1)
        }
    }

    private static func validate<ID: Hashable & Sendable>(
        _ assignments: [Assignment<ID>],
        expectedIDs: [ID]
    ) throws {
        let assignmentsByID = Dictionary(
            uniqueKeysWithValues: assignments.map { ($0.id, $0.order) }
        )
        guard assignments.allSatisfy({
            FractionalIndex.isValid($0.order)
        }) else {
            throw PlanningError.invalidResult
        }

        if assignments.count == expectedIDs.count {
            let assignedOrders = expectedIDs.compactMap {
                assignmentsByID[$0]
            }
            guard assignedOrders.count == expectedIDs.count else {
                throw PlanningError.invalidResult
            }
            guard zip(assignedOrders, assignedOrders.dropFirst()).allSatisfy(<)
            else {
                throw PlanningError.invalidResult
            }
        }
    }
}
