import Foundation

/// Collapses the former low tier after the regular projects without letting
/// their independently allocated order keys interleave the two groups.
/// Legacy records arriving in a later sync batch append to the merged group;
/// existing regular positions are retained whenever their keys remain valid.
nonisolated enum ProjectPriorityMigration {
    struct Entry {
        let id: UUID
        let priority: ProjectPriority
        let isLegacyLow: Bool
        let order: String
    }

    static func orderingChanges(
        for entries: [Entry]
    ) throws -> [ProjectOrderingChange] {
        let legacyLow = entries.filter(\.isLegacyLow).sorted(by: precedes)
        guard !legacyLow.isEmpty else { return [] }

        let normal = entries.filter {
            $0.priority == .normal && !$0.isLegacyLow
        }.sorted(by: precedes)
        let normalEntries = normal.map {
            OrderingPlanner.Entry(id: $0.id, order: $0.order)
        }
        let repairs: [OrderingPlanner.Assignment<UUID>]
        if normalEntries.allSatisfy({ FractionalIndex.isValid($0.order) }) {
            repairs = []
        } else {
            repairs = try OrderingPlanner.displayedOrder(
                normal.map(\.id),
                contains: normalEntries
            ).assignments
        }
        let destination = repairs.isEmpty ? normalEntries : repairs.map {
            OrderingPlanner.Entry(id: $0.id, order: $0.order)
        }
        let plan = try OrderingPlanner.move(
            legacyLow.map(\.id),
            before: nil,
            in: destination,
            sourceEntries: legacyLow.map {
                OrderingPlanner.Entry(id: $0.id, order: $0.order)
            },
            validatesSourceOrders: false
        )
        return (repairs + plan.assignments).map {
            ProjectOrderingChange(id: $0.id, order: $0.order, priority: .normal)
        }
    }

    private static func precedes(_ lhs: Entry, _ rhs: Entry) -> Bool {
        if lhs.order != rhs.order { return lhs.order < rhs.order }
        return lhs.id.uuidString < rhs.id.uuidString
    }
}
