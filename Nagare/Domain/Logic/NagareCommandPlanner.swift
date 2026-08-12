import Foundation

/// Pure policy for create/edit commands. Persistence receives a complete plan
/// and has no reason to calculate list positions or infer project membership.
nonisolated enum NagareCommandPlanner {
    enum PlanningError: Error, Equatable, Sendable {
        case missingItem
        case missingProject
        case invalidResult
    }

    static func upsertItem(
        _ draft: ItemDraft,
        existingID: ItemID?,
        in snapshot: NagareDataSnapshot,
        calendar: Calendar
    ) throws -> ItemUpsertPlan {
        let items = allItems(in: snapshot)
        let existing: ItemRecordSnapshot?
        if let existingID {
            guard let item = item(existingID, in: snapshot) else {
                throw PlanningError.missingItem
            }
            existing = item
        } else {
            existing = nil
        }

        let orderPlan: OrderingPlanner.NextOrderPlan<ItemID>?
        if let existing,
           calendar.isDate(
               existing.scheduledDate,
               inSameDayAs: draft.scheduledDate
           ) {
            orderPlan = nil
        } else {
            orderPlan = try OrderingPlanner.nextOrder(
                after: ordered(items.filter { $0.id != existingID }).map {
                    OrderingPlanner.Entry(id: $0.id, order: $0.order)
                }
            )
        }

        let projectOrderPlan: OrderingPlanner.NextOrderPlan<ItemID>?
        if let projectID = draft.projectID {
            guard snapshot.projectsByID[projectID] != nil else {
                throw PlanningError.missingProject
            }
            if existing?.projectID == projectID,
               let projectOrder = existing?.projectOrder,
               FractionalIndex.isValid(projectOrder) {
                projectOrderPlan = nil
            } else {
                let projectItems = orderedInProject(items.filter {
                    $0.id != existingID
                        && $0.projectID == projectID
                        && !$0.isCompleted
                })
                projectOrderPlan = try OrderingPlanner.nextOrder(
                    after: projectItems.map {
                        OrderingPlanner.Entry(
                            id: $0.id,
                            order: $0.projectOrder ?? ""
                        )
                    }
                )
            }
        } else {
            projectOrderPlan = nil
        }

        guard let order = orderPlan?.order ?? existing?.order else {
            throw PlanningError.invalidResult
        }
        let projectOrder: String?
        if draft.projectID == nil {
            projectOrder = nil
        } else {
            guard let resolvedProjectOrder = projectOrderPlan?.order
                ?? existing?.projectOrder else {
                throw PlanningError.invalidResult
            }
            projectOrder = resolvedProjectOrder
        }

        return ItemUpsertPlan(
            draft: draft,
            existingID: existingID,
            order: order,
            orderRepairs: orderPlan?.repairs.map {
                ItemOrderingChange(id: $0.id, order: $0.order)
            } ?? [],
            projectOrder: projectOrder,
            projectOrderRepairs: projectOrderPlan?.repairs.map {
                ProjectItemOrderingChange(
                    id: $0.id,
                    projectOrder: $0.order
                )
            } ?? []
        )
    }

    static func upsertProject(
        _ draft: ProjectDraft,
        existingID: UUID?,
        in snapshot: NagareDataSnapshot
    ) throws -> ProjectUpsertPlan {
        if let existingID {
            guard let existing = snapshot.projectsByID[existingID] else {
                throw PlanningError.missingProject
            }
            return ProjectUpsertPlan(
                draft: draft,
                existingID: existingID,
                order: existing.order,
                orderRepairs: []
            )
        }

        let projects = snapshot.canonicalProjects
            .filter { !$0.isPriority }
            .sorted {
                if $0.order != $1.order { return $0.order < $1.order }
                return $0.id.uuidString < $1.id.uuidString
            }
        let orderPlan = try OrderingPlanner.nextOrder(
            after: projects.map {
                OrderingPlanner.Entry(id: $0.id, order: $0.order)
            }
        )
        return ProjectUpsertPlan(
            draft: draft,
            existingID: nil,
            order: orderPlan.order,
            orderRepairs: orderPlan.repairs.map {
                ProjectOrderingChange(id: $0.id, order: $0.order)
            }
        )
    }

    static func upsertCalendarEvent(
        _ draft: ICalendarEventDraft,
        in snapshot: NagareDataSnapshot
    ) throws -> CalendarEventUpsertPlan {
        if let existing = snapshot.canonicalEvents.first(where: {
            $0.calendarIdentifier == draft.sourceIdentifier
        }) {
            return CalendarEventUpsertPlan(
                draft: draft,
                order: existing.order,
                orderRepairs: []
            )
        }

        let items = ordered(allItems(in: snapshot))
        let orderPlan = try OrderingPlanner.nextOrder(
            after: items.map {
                OrderingPlanner.Entry(id: $0.id, order: $0.order)
            }
        )
        return CalendarEventUpsertPlan(
            draft: draft,
            order: orderPlan.order,
            orderRepairs: orderPlan.repairs.map {
                ItemOrderingChange(id: $0.id, order: $0.order)
            }
        )
    }

    static func assign(
        _ target: ProjectMoveRecordID,
        to projectID: UUID?,
        in snapshot: NagareDataSnapshot
    ) throws -> ProjectAssignmentPlan {
        if let projectID,
           snapshot.projectsByID[projectID] == nil {
            throw PlanningError.missingProject
        }

        let assignedItem: ItemRecordSnapshot
        let recurrenceTemplateID: UUID?
        switch target {
        case .item(let id):
            guard let existing = item(id, in: snapshot) else {
                throw PlanningError.missingItem
            }
            assignedItem = existing
            switch existing {
            case .todo(let todo):
                recurrenceTemplateID = todo.recurrenceTemplateID
            case .event(let event):
                recurrenceTemplateID = event.recurrenceTemplateID
            }
        case .recurrenceTemplate(let id):
            guard let template = snapshot.templatesByID[id],
                  let current = snapshot.currentItem(for: template) else {
                throw PlanningError.missingItem
            }
            assignedItem = current
            recurrenceTemplateID = id
        }

        let projectOrderPlan: OrderingPlanner.NextOrderPlan<ItemID>?
        if let projectID {
            if assignedItem.projectID == projectID,
               assignedItem.projectOrder.map(FractionalIndex.isValid) == true {
                projectOrderPlan = nil
            } else {
                let destination = orderedInProject(allItems(in: snapshot).filter {
                    $0.id != assignedItem.id
                        && $0.projectID == projectID
                        && !$0.isCompleted
                })
                projectOrderPlan = try OrderingPlanner.nextOrder(
                    after: destination.map {
                        OrderingPlanner.Entry(
                            id: $0.id,
                            order: $0.projectOrder ?? ""
                        )
                    }
                )
            }
        } else {
            projectOrderPlan = nil
        }

        let projectOrder: String?
        if projectID == nil {
            projectOrder = nil
        } else {
            guard let resolved = projectOrderPlan?.order
                ?? assignedItem.projectOrder else {
                throw PlanningError.invalidResult
            }
            projectOrder = resolved
        }

        return ProjectAssignmentPlan(
            itemID: assignedItem.id,
            recurrenceTemplateID: recurrenceTemplateID,
            projectID: projectID,
            projectOrder: projectOrder,
            projectOrderRepairs: projectOrderPlan?.repairs.map {
                ProjectItemOrderingChange(
                    id: $0.id,
                    projectOrder: $0.order
                )
            } ?? []
        )
    }

    static func reinstateTodo(
        _ id: UUID,
        on date: Date,
        in snapshot: NagareDataSnapshot,
        calendar: Calendar
    ) throws -> TodoReinstatementPlan {
        guard let todo = snapshot.todosByID[id],
              todo.completedAt != nil else {
            throw PlanningError.missingItem
        }

        let items = allItems(in: snapshot)
        let orderPlan = try OrderingPlanner.nextOrder(
            after: ordered(items).map {
                OrderingPlanner.Entry(id: $0.id, order: $0.order)
            }
        )

        let projectOrderPlan: OrderingPlanner.NextOrderPlan<ItemID>?
        if let projectID = todo.projectID {
            let projectItems = orderedInProject(items.filter {
                $0.id != .todo(id)
                    && $0.projectID == projectID
                    && !$0.isCompleted
            })
            projectOrderPlan = try OrderingPlanner.nextOrder(
                after: projectItems.map {
                    OrderingPlanner.Entry(
                        id: $0.id,
                        order: $0.projectOrder ?? ""
                    )
                }
            )
        } else {
            projectOrderPlan = nil
        }

        return TodoReinstatementPlan(
            id: id,
            scheduledDate: calendar.startOfDay(for: date),
            order: orderPlan.order,
            orderRepairs: orderPlan.repairs.map {
                ItemOrderingChange(id: $0.id, order: $0.order)
            },
            projectOrder: projectOrderPlan?.order,
            projectOrderRepairs: projectOrderPlan?.repairs.map {
                ProjectItemOrderingChange(
                    id: $0.id,
                    projectOrder: $0.order
                )
            } ?? []
        )
    }

    private static func allItems(
        in snapshot: NagareDataSnapshot
    ) -> [ItemRecordSnapshot] {
        snapshot.canonicalTodos.map(ItemRecordSnapshot.todo)
            + snapshot.canonicalEvents.map(ItemRecordSnapshot.event)
    }

    private static func item(
        _ id: ItemID,
        in snapshot: NagareDataSnapshot
    ) -> ItemRecordSnapshot? {
        switch id {
        case .todo(let id):
            snapshot.todosByID[id].map(ItemRecordSnapshot.todo)
        case .event(let id):
            snapshot.eventsByID[id].map(ItemRecordSnapshot.event)
        }
    }

    private static func ordered(
        _ items: [ItemRecordSnapshot]
    ) -> [ItemRecordSnapshot] {
        items.sorted {
            if $0.order != $1.order { return $0.order < $1.order }
            return $0.id.description < $1.id.description
        }
    }

    private static func orderedInProject(
        _ items: [ItemRecordSnapshot]
    ) -> [ItemRecordSnapshot] {
        items.sorted {
            switch ($0.projectOrder, $1.projectOrder) {
            case let (.some(lhs), .some(rhs)) where lhs != rhs:
                return lhs < rhs
            case (.some, .none): return true
            case (.none, .some): return false
            default: return $0.id.description < $1.id.description
            }
        }
    }

}
