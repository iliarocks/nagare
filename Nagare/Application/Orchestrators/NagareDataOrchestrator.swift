import Foundation

/// One lamination point: pure plans enter through immutable values, the port
/// performs one transaction, and the repository is read again before state is
/// published. No managed object survives either operation.
@MainActor
final class NagareDataOrchestrator {
    private let reader: any NagareDataReading
    private let writer: any NagareDataWriting

    init(
        reader: any NagareDataReading,
        writer: any NagareDataWriting
    ) {
        self.reader = reader
        self.writer = writer
    }

    func load() throws -> NagareDataSnapshot {
        try reader.load()
    }

    func upsertItem(
        _ draft: ItemDraft,
        existingID: ItemID?,
        calendar: Calendar,
        at date: Date
    ) throws -> (id: ItemID, snapshot: NagareDataSnapshot) {
        let current = try reader.load()
        let plan = try NagareCommandPlanner.upsertItem(
            draft,
            existingID: existingID,
            in: current,
            calendar: calendar
        )
        let id = try writer.upsertItem(
            plan,
            at: date
        )
        return (id, try reader.load())
    }

    func upsertProject(
        _ draft: ProjectDraft,
        existingID: UUID?,
        at date: Date
    ) throws -> (id: UUID, snapshot: NagareDataSnapshot) {
        let current = try reader.load()
        let plan = try NagareCommandPlanner.upsertProject(
            draft,
            existingID: existingID,
            in: current
        )
        let id = try writer.upsertProject(
            plan,
            at: date
        )
        return (id, try reader.load())
    }

    func updateNote(
        _ id: NoteRecordID,
        title: String,
        notes: String?,
        at date: Date
    ) throws -> NagareDataSnapshot {
        try writer.updateNote(id, title: title, notes: notes, at: date)
        return try reader.load()
    }

    func updateProject(
        _ id: UUID,
        title: String,
        notes: String?,
        at date: Date
    ) throws -> NagareDataSnapshot {
        try writer.updateProject(id, title: title, notes: notes, at: date)
        return try reader.load()
    }

    func saveItemOrdering(
        _ changes: [ItemOrderingChange],
        at date: Date
    ) throws -> NagareDataSnapshot {
        try writer.saveItemOrdering(changes, at: date)
        return try reader.load()
    }

    func saveProjectOrdering(
        _ changes: [ProjectOrderingChange],
        at date: Date
    ) throws -> NagareDataSnapshot {
        try writer.saveProjectOrdering(changes, at: date)
        return try reader.load()
    }

    func reorderProjects(
        _ displayedIDs: [UUID],
        isPriority: Bool,
        at date: Date
    ) throws -> NagareDataSnapshot {
        let current = try reader.load()
        let projects = current.canonicalProjects
            .filter { $0.isPriority == isPriority }
            .sorted {
                if $0.order != $1.order { return $0.order < $1.order }
                return $0.id.uuidString < $1.id.uuidString
            }
        let plan = try OrderingPlanner.displayedOrder(
            displayedIDs,
            contains: projects.map {
                OrderingPlanner.Entry(id: $0.id, order: $0.order)
            }
        )
        try writer.saveProjectOrdering(
            plan.assignments.map {
                ProjectOrderingChange(id: $0.id, order: $0.order)
            },
            at: date
        )
        return try reader.load()
    }

    func moveProjects(
        _ sourceIDs: [UUID],
        toPriority isPriority: Bool,
        before destinationID: UUID?,
        at date: Date
    ) throws -> NagareDataSnapshot {
        let current = try reader.load()
        let projectsByID = current.projectsByID
        let source = try sourceIDs.map { id in
            guard let project = projectsByID[id] else {
                throw OrderingPlanner.PlanningError.missingSource
            }
            return project
        }
        let destination = current.canonicalProjects
            .filter { $0.isPriority == isPriority }
            .sorted {
                if $0.order != $1.order { return $0.order < $1.order }
                return $0.id.uuidString < $1.id.uuidString
            }
        let preparedDestination = try prepareEntries(
            destination.map { ($0.id, Optional($0.order)) }
        )
        let plan = try OrderingPlanner.move(
            sourceIDs,
            before: destinationID,
            in: preparedDestination.entries,
            sourceEntries: source.map {
                OrderingPlanner.Entry(id: $0.id, order: $0.order)
            },
            validatesSourceOrders: false
        )
        try writer.saveProjectOrdering(
            preparedDestination.repairs.map {
                ProjectOrderingChange(id: $0.id, order: $0.order)
            } + plan.assignments.map {
                ProjectOrderingChange(
                    id: $0.id,
                    order: $0.order,
                    isPriority: isPriority
                )
            },
            at: date
        )
        return try reader.load()
    }

    func moveProjectItems(
        _ sourceIDs: [ItemID],
        before destinationID: ItemID?,
        projectID: UUID,
        at date: Date
    ) throws -> NagareDataSnapshot {
        let current = try reader.load()
        let items = Array(current.itemsByID.values)
            .filter { $0.projectID == projectID && !$0.isCompleted }
            .sorted {
                switch ($0.projectOrder, $1.projectOrder) {
                case let (.some(lhs), .some(rhs)) where lhs != rhs:
                    return lhs < rhs
                case (.some, .none): return true
                case (.none, .some): return false
                default: return $0.id.description < $1.id.description
                }
            }
        let itemsByID = Dictionary(
            items.map { ($0.id, $0) },
            uniquingKeysWith: { current, _ in current }
        )
        let source = try sourceIDs.map { id in
            guard let item = itemsByID[id] else {
                throw OrderingPlanner.PlanningError.missingSource
            }
            return item
        }
        let preparedItems = try prepareEntries(
            items.map { ($0.id, $0.projectOrder) }
        )
        let preparedByID = Dictionary(
            preparedItems.entries.map {
                ($0.id, $0)
            },
            uniquingKeysWith: { current, _ in current }
        )
        let plan = try OrderingPlanner.move(
            sourceIDs,
            before: destinationID,
            in: preparedItems.entries,
            sourceEntries: try source.map {
                guard let entry = preparedByID[$0.id] else {
                    throw OrderingPlanner.PlanningError.missingSource
                }
                return entry
            }
        )
        try writer.saveProjectItemOrdering(
            preparedItems.repairs.map {
                ProjectItemOrderingChange(
                    id: $0.id,
                    projectOrder: $0.order
                )
            } + plan.assignments.map {
                ProjectItemOrderingChange(
                    id: $0.id,
                    projectOrder: $0.order
                )
            },
            at: date
        )
        return try reader.load()
    }

    func deleteProject(
        _ id: UUID,
        at date: Date
    ) throws -> NagareDataSnapshot {
        try writer.deleteProject(id, at: date)
        return try reader.load()
    }

    func completeTodo(
        _ id: UUID,
        at date: Date
    ) throws -> NagareDataSnapshot {
        try writer.completeTodo(id, at: date)
        return try reader.load()
    }

    func reinstateTodo(
        _ id: UUID,
        on date: Date,
        calendar: Calendar,
        at transactionDate: Date
    ) throws -> NagareDataSnapshot {
        let current = try reader.load()
        let plan = try NagareCommandPlanner.reinstateTodo(
            id,
            on: date,
            in: current,
            calendar: calendar
        )
        try writer.reinstateTodo(plan, at: transactionDate)
        return try reader.load()
    }

    func deleteCompletedTodo(
        _ id: UUID,
        at date: Date
    ) throws -> NagareDataSnapshot {
        try writer.deleteCompletedTodo(id, at: date)
        return try reader.load()
    }

    func performMaintenance(
        at date: Date,
        calendar: Calendar
    ) throws -> NagareDataSnapshot {
        let current = try reader.load()
        let items = current.canonicalTodos.map {
            ItemRecordSnapshot.todo($0).orderingSnapshot
        } + current.canonicalEvents.map {
            ItemRecordSnapshot.event($0).orderingSnapshot
        }
        let todoPlan = try TodoMaintenanceLogic.rollForward(
            items,
            to: date,
            calendar: calendar
        )
        if !todoPlan.changes.isEmpty {
            try writer.saveItemOrdering(todoPlan.changes, at: date)
        }
        try writer.deletePastEvents(
            before: calendar.startOfDay(for: date),
            at: date
        )
        return try reader.load()
    }

    func deleteItem(
        _ id: ItemID,
        at date: Date
    ) throws -> NagareDataSnapshot {
        try writer.deleteItem(id, at: date)
        return try reader.load()
    }

    func deleteItems(
        _ ids: [ItemID],
        at date: Date
    ) throws -> NagareDataSnapshot {
        try writer.deleteItems(ids, at: date)
        return try reader.load()
    }

    func deleteRecurrenceTemplate(
        _ id: UUID,
        at date: Date
    ) throws -> NagareDataSnapshot {
        try writer.deleteRecurrenceTemplate(id, at: date)
        return try reader.load()
    }

    func moveItems(
        _ sourceIDs: [ItemID],
        to destinationDate: Date,
        before destinationID: ItemID?,
        calendar: Calendar,
        at date: Date
    ) throws -> NagareDataSnapshot {
        let current = try reader.load()
        let itemsByID = current.itemsByID
        let allItems = Array(itemsByID.values)
        let sourceItems = try sourceIDs.map { id in
            guard let item = itemsByID[id] else {
                throw OrderingPlanner.PlanningError.missingSource
            }
            return item
        }
        let destinationDay = calendar.startOfDay(for: destinationDate)
        let destinationItems = allItems.filter {
            calendar.isDate($0.scheduledDate, inSameDayAs: destinationDay)
                && !$0.isCompleted
        }.sorted {
            if $0.order != $1.order { return $0.order < $1.order }
            return $0.id.description < $1.id.description
        }
        let preparedDestination = try prepareEntries(
            destinationItems.map { ($0.id, Optional($0.order)) }
        )
        let plan = try OrderingPlanner.move(
            sourceIDs,
            before: destinationID,
            in: preparedDestination.entries,
            sourceEntries: sourceItems.map {
                OrderingPlanner.Entry(id: $0.id, order: $0.order)
            },
            validatesSourceOrders: false
        )
        let orderChanges = preparedDestination.repairs.map {
            ItemOrderingChange(id: $0.id, order: $0.order)
        } + plan.assignments.map {
            ItemOrderingChange(id: $0.id, order: $0.order)
        }
        let scheduleChanges = sourceItems.map {
            ItemScheduleLogic.moving(
                $0.orderingSnapshot,
                to: destinationDay,
                calendar: calendar
            )
        }
        try writer.saveItemOrdering(orderChanges + scheduleChanges, at: date)
        return try reader.load()
    }

    func updateEventSchedule(
        _ id: UUID,
        scheduledDate: Date,
        endDate: Date?,
        calendar: Calendar,
        at date: Date
    ) throws -> NagareDataSnapshot {
        let current = try reader.load()
        guard let event = current.eventsByID[id] else {
            throw OrderingPlanner.PlanningError.missingSource
        }
        var changes: [ItemOrderingChange] = []
        if !calendar.isDate(event.scheduledDate, inSameDayAs: scheduledDate) {
            let destination = ItemRecordSnapshot.ordered(
                todos: current.canonicalTodos.filter {
                    $0.completedAt == nil
                        && calendar.isDate(
                            $0.scheduledDate,
                            inSameDayAs: scheduledDate
                        )
                },
                events: current.canonicalEvents.filter {
                    $0.id != id
                        && calendar.isDate(
                            $0.scheduledDate,
                            inSameDayAs: scheduledDate
                        )
                }
            )
            let next = try OrderingPlanner.nextOrder(
                after: destination.map {
                    OrderingPlanner.Entry(id: $0.id, order: $0.order)
                }
            )
            changes += next.repairs.map {
                ItemOrderingChange(id: $0.id, order: $0.order)
            }
            changes.append(
                ItemOrderingChange(
                    id: .event(id),
                    order: next.order,
                    scheduledDate: scheduledDate,
                    endDate: endDate
                )
            )
        } else {
            changes.append(
                ItemOrderingChange(
                    id: .event(id),
                    scheduledDate: scheduledDate,
                    endDate: endDate
                )
            )
        }
        try writer.saveItemOrdering(changes, at: date)
        return try reader.load()
    }

    func assign(
        _ target: ProjectMoveRecordID,
        to projectID: UUID?,
        at date: Date
    ) throws -> NagareDataSnapshot {
        let current = try reader.load()
        let plan = try NagareCommandPlanner.assign(
            target,
            to: projectID,
            in: current
        )
        try writer.assign(plan, at: date)
        return try reader.load()
    }

    func assign(
        _ targets: [ProjectMoveRecordID],
        to projectID: UUID?,
        at date: Date
    ) throws -> NagareDataSnapshot {
        let current = try reader.load()
        let plan = try NagareCommandPlanner.assign(
            targets,
            to: projectID,
            in: current
        )
        try writer.assign(plan, at: date)
        return try reader.load()
    }

    func updateRecurrenceTemplate(
        _ id: UUID,
        rule: RecurrenceRule,
        eventStartTimeSeconds: Int?,
        eventEndTimeSeconds: Int?,
        at date: Date
    ) throws -> NagareDataSnapshot {
        try writer.updateRecurrenceTemplate(
            id,
            rule: rule,
            eventStartTimeSeconds: eventStartTimeSeconds,
            eventEndTimeSeconds: eventEndTimeSeconds,
            at: date
        )
        return try reader.load()
    }

    /// Converts legacy or partial-import order values into one valid immutable
    /// input and carries the repair assignments into the same transaction as
    /// the requested move.
    private func prepareEntries<ID: Hashable & Sendable>(
        _ values: [(id: ID, order: String?)]
    ) throws -> (
        entries: [OrderingPlanner.Entry<ID>],
        repairs: [OrderingPlanner.Assignment<ID>]
    ) {
        let entries = values.map {
            OrderingPlanner.Entry(id: $0.id, order: $0.order ?? "")
        }
        guard !entries.allSatisfy({
            FractionalIndex.isValid($0.order)
        }) else {
            return (entries, [])
        }
        let repair = try OrderingPlanner.displayedOrder(
            values.map(\.id),
            contains: entries
        )
        return (
            repair.assignments.map {
                OrderingPlanner.Entry(id: $0.id, order: $0.order)
            },
            repair.assignments
        )
    }
}
