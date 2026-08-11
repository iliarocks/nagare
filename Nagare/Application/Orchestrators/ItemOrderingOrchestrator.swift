import Foundation

/// Laminates immutable snapshots, pure planning, and an I/O port.
@MainActor
enum ItemOrderingOrchestrator {
    enum Outcome: Equatable {
        case noChange
        case saved
    }

    static func prepareNextOrder(
        using persistence: any ItemOrderingPersistence
    ) throws -> String {
        let items = try loadItems(using: persistence)
        let entries = ordered(items).map {
            OrderingPlanner.Entry(id: $0.id, order: $0.order)
        }
        let plan = try OrderingPlanner.nextOrder(after: entries)
        guard !plan.repairs.isEmpty else {
            return plan.order
        }

        do {
            try persistence.apply(plan.repairs.map {
                ItemOrderingChange(id: $0.id, order: $0.order)
            })
            return plan.order
        } catch {
            persistence.rollback()
            throw persistenceFailure(error, operation: .apply)
        }
    }

    static func move(
        _ sourceIDs: [ItemID],
        to destinationDate: Date,
        before destinationID: ItemID?,
        using persistence: any ItemOrderingPersistence,
        calendar: Calendar
    ) throws -> Outcome {
        let items = try loadItems(using: persistence)
        let itemsByID = Dictionary(
            uniqueKeysWithValues: items.map { ($0.id, $0) }
        )
        let sourceItems = try sourceIDs.map { sourceID in
            guard let item = itemsByID[sourceID] else {
                throw OrderingPlanner.PlanningError.missingSource
            }
            return item
        }

        let destinationDay = calendar.startOfDay(for: destinationDate)
        let destinationItems = ordered(items.filter {
            calendar.isDate($0.scheduledDate, inSameDayAs: destinationDay)
                && !$0.isCompleted
        })
        let plan = try OrderingPlanner.move(
            sourceIDs,
            before: destinationID,
            in: destinationItems.map {
                OrderingPlanner.Entry(id: $0.id, order: $0.order)
            },
            sourceEntries: sourceItems.map {
                OrderingPlanner.Entry(id: $0.id, order: $0.order)
            }
        )

        if plan.orderedIDs == destinationItems.map(\.id),
           sourceItems.allSatisfy({
               calendar.isDate(
                   $0.scheduledDate,
                   inSameDayAs: destinationDay
               )
           }) {
            return .noChange
        }

        let orderChanges = plan.assignments.map {
            ItemOrderingChange(id: $0.id, order: $0.order)
        }
        let scheduleChanges = sourceItems.map {
            ItemScheduleLogic.moving(
                $0,
                to: destinationDay,
                calendar: calendar
            )
        }
        do {
            try persistence.apply(orderChanges + scheduleChanges)
            try persistence.save()
            return .saved
        } catch {
            persistence.rollback()
            throw persistenceFailure(
                error,
                operation: .save
            )
        }
    }

    static func saveDisplayedOrder(
        _ itemIDs: [ItemID],
        on date: Date,
        using persistence: any ItemOrderingPersistence,
        calendar: Calendar
    ) throws {
        let day = calendar.startOfDay(for: date)
        let items = ordered(try loadItems(using: persistence).filter {
            calendar.isDate($0.scheduledDate, inSameDayAs: day)
                && !$0.isCompleted
        })
        let plan = try OrderingPlanner.displayedOrder(
            itemIDs,
            contains: items.map {
                OrderingPlanner.Entry(id: $0.id, order: $0.order)
            }
        )

        do {
            try persistence.apply(plan.assignments.map {
                ItemOrderingChange(id: $0.id, order: $0.order)
            })
            try persistence.save()
        } catch {
            persistence.rollback()
            throw persistenceFailure(
                error,
                operation: .save
            )
        }
    }

    static func moveWithinProject(
        _ sourceIDs: [ItemID],
        before destinationID: ItemID?,
        projectID: UUID,
        using persistence: any ItemOrderingPersistence
    ) throws {
        let allItems = try loadItems(using: persistence)
        let currentItems = orderedInProject(allItems.filter {
            $0.projectID == projectID && !$0.isCompleted
        })
        let itemsByID = Dictionary(
            uniqueKeysWithValues: currentItems.map { ($0.id, $0) }
        )
        let sourceEntries = try sourceIDs.map { id in
            guard let item = itemsByID[id],
                  let order = item.projectOrder else {
                throw OrderingPlanner.PlanningError.missingSource
            }
            return OrderingPlanner.Entry(id: id, order: order)
        }
        let plan = try OrderingPlanner.move(
            sourceIDs,
            before: destinationID,
            in: try currentItems.map { item in
                guard let order = item.projectOrder else {
                    throw OrderingPlanner.PlanningError.invalidOrderKey
                }
                return OrderingPlanner.Entry(id: item.id, order: order)
            },
            sourceEntries: sourceEntries
        )
        guard plan.orderedIDs != currentItems.map(\.id) else {
            return
        }

        do {
            try persistence.applyProjectOrder(plan.assignments.map {
                ProjectItemOrderingChange(
                    id: $0.id,
                    projectOrder: $0.order
                )
            })
            try persistence.save()
        } catch {
            persistence.rollback()
            throw persistenceFailure(
                error,
                operation: .save
            )
        }
    }

    static func prepareNextProjectItemOrder(
        projectID: UUID,
        using persistence: any ItemOrderingPersistence
    ) throws -> String {
        let items = orderedInProject(try loadItems(using: persistence).filter {
            $0.projectID == projectID && !$0.isCompleted
        })
        let entries = try items.map { item in
            guard let order = item.projectOrder else {
                throw OrderingPlanner.PlanningError.invalidOrderKey
            }
            return OrderingPlanner.Entry(id: item.id, order: order)
        }
        let plan = try OrderingPlanner.nextOrder(after: entries)
        if !plan.repairs.isEmpty {
            do {
                try persistence.applyProjectOrder(plan.repairs.map {
                    ProjectItemOrderingChange(
                        id: $0.id,
                        projectOrder: $0.order
                    )
                })
            } catch {
                persistence.rollback()
                throw persistenceFailure(error, operation: .apply)
            }
        }
        return plan.order
    }

    private static func loadItems(
        using persistence: any ItemOrderingPersistence
    ) throws -> [ItemSnapshot] {
        do {
            return try persistence.loadItems()
        } catch {
            persistence.rollback()
            throw persistenceFailure(error, operation: .load)
        }
    }

    private static func ordered(_ items: [ItemSnapshot]) -> [ItemSnapshot] {
        items.sorted {
            if $0.order != $1.order {
                return $0.order < $1.order
            }
            return $0.id.description < $1.id.description
        }
    }

    private static func orderedInProject(
        _ items: [ItemSnapshot]
    ) -> [ItemSnapshot] {
        items.sorted {
            switch ($0.projectOrder, $1.projectOrder) {
            case let (.some(first), .some(second)) where first != second:
                return first < second
            case (.some, .none):
                return true
            case (.none, .some):
                return false
            default:
                return $0.id.description < $1.id.description
            }
        }
    }
}

private extension ItemOrderingOrchestrator {
    enum PersistenceOperation {
        case load
        case apply
        case save
    }

    static func persistenceFailure(
        _ error: Error,
        operation: PersistenceOperation
    ) -> OrderingPersistenceError {
        if let error = error as? OrderingPersistenceError {
            return error
        }
        switch operation {
        case .load:
            return .loadFailed(error.localizedDescription)
        case .apply:
            return .applyFailed(error.localizedDescription)
        case .save:
            return .saveFailed(error.localizedDescription)
        }
    }
}
