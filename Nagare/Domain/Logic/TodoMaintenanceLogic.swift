import Foundation

nonisolated enum TodoMaintenanceLogic {
    struct Plan: Equatable, Sendable {
        let changes: [ItemOrderingChange]
    }

    /// Computes the complete roll-forward transition without touching storage.
    static func rollForward(
        _ items: [ItemSnapshot],
        to today: Date,
        calendar: Calendar
    ) throws -> Plan {
        let today = calendar.startOfDay(for: today)
        let orderedItems = items.sorted(by: itemOrder)
        let nextOrderPlan = try OrderingPlanner.nextOrder(
            after: orderedItems.map {
                OrderingPlanner.Entry(id: $0.id, order: $0.order)
            }
        )
        var changes = nextOrderPlan.repairs.map {
            ItemOrderingChange(id: $0.id, order: $0.order)
        }
        var previousOrder = nextOrderPlan.order

        let overdueTodos = items
            .filter {
                !$0.isCompleted
                    && $0.scheduledDate < today
            }
            .sorted {
                if $0.scheduledDate != $1.scheduledDate {
                    return $0.scheduledDate < $1.scheduledDate
                }
                if $0.order != $1.order {
                    return $0.order < $1.order
                }
                if $0.createdAt != $1.createdAt {
                    return $0.createdAt < $1.createdAt
                }
                return $0.id.description < $1.id.description
            }

        for todo in overdueTodos {
            let movedSchedule = ItemScheduleLogic.moving(
                todo,
                to: today,
                calendar: calendar
            )
            changes.append(
                ItemOrderingChange(
                    id: todo.id,
                    order: previousOrder,
                    scheduledDate: movedSchedule.scheduledDate,
                    endDate: movedSchedule.endDate
                )
            )
            guard let followingOrder = FractionalIndex.between(
                previousOrder,
                nil
            ) else {
                throw OrderingPlanner.PlanningError.invalidResult
            }
            previousOrder = followingOrder
        }
        return Plan(changes: changes)
    }

    private static func itemOrder(
        _ first: ItemSnapshot,
        _ second: ItemSnapshot
    ) -> Bool {
        if first.order != second.order {
            return first.order < second.order
        }
        return first.id.description < second.id.description
    }
}
