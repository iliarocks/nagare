import Foundation

/// Laminates project snapshots, shared pure ordering logic, and persistence.
@MainActor
enum ProjectOrderingOrchestrator {
    static func prepareNextOrder(
        isPriority: Bool,
        using persistence: any ProjectOrderingPersistence
    ) throws -> String {
        let projects = ordered(
            try loadProjects(using: persistence).filter {
                $0.isPriority == isPriority
            }
        )
        let plan = try OrderingPlanner.nextOrder(
            after: projects.map {
                OrderingPlanner.Entry(id: $0.id, order: $0.order)
            }
        )
        if !plan.repairs.isEmpty {
            do {
                try persistence.apply(plan.repairs.map {
                    ProjectOrderingChange(id: $0.id, order: $0.order)
                })
            } catch {
                persistence.rollback()
                throw orderingPersistenceError(error, applying: true)
            }
        }
        return plan.order
    }

    static func move(
        _ sourceIDs: [UUID],
        toPriority isPriority: Bool,
        before destinationID: UUID?,
        using persistence: any ProjectOrderingPersistence
    ) throws {
        let allProjects = try loadProjects(using: persistence)
        let projectsByID = Dictionary(
            uniqueKeysWithValues: allProjects.map { ($0.id, $0) }
        )
        let sourceProjects = try sourceIDs.map { id in
            guard let project = projectsByID[id] else {
                throw OrderingPlanner.PlanningError.missingSource
            }
            return project
        }
        let destination = ordered(allProjects.filter {
            $0.isPriority == isPriority
        })
        let plan = try OrderingPlanner.move(
            sourceIDs,
            before: destinationID,
            in: destination.map {
                OrderingPlanner.Entry(id: $0.id, order: $0.order)
            },
            sourceEntries: sourceProjects.map {
                OrderingPlanner.Entry(id: $0.id, order: $0.order)
            },
            validatesSourceOrders: false
        )
        if plan.orderedIDs == destination.map(\.id),
           sourceProjects.allSatisfy({ $0.isPriority == isPriority }) {
            return
        }

        let orderChanges = plan.assignments.map {
            ProjectOrderingChange(id: $0.id, order: $0.order)
        }
        let tierChanges = sourceProjects.map {
            ProjectOrderingChange(id: $0.id, isPriority: isPriority)
        }
        do {
            try persistence.apply(orderChanges + tierChanges)
            try persistence.save()
        } catch {
            persistence.rollback()
            throw orderingPersistenceError(
                error,
                applying: error is OrderingPersistenceError
            )
        }
    }

    static func saveDisplayedOrder(
        _ projectIDs: [UUID],
        isPriority: Bool,
        using persistence: any ProjectOrderingPersistence
    ) throws {
        let projects = ordered(
            try loadProjects(using: persistence).filter {
                $0.isPriority == isPriority
            }
        )
        let plan = try OrderingPlanner.displayedOrder(
            projectIDs,
            contains: projects.map {
                OrderingPlanner.Entry(id: $0.id, order: $0.order)
            }
        )
        do {
            try persistence.apply(plan.assignments.map {
                ProjectOrderingChange(id: $0.id, order: $0.order)
            })
            try persistence.save()
        } catch {
            persistence.rollback()
            throw orderingPersistenceError(
                error,
                applying: error is OrderingPersistenceError
            )
        }
    }

    private static func loadProjects(
        using persistence: any ProjectOrderingPersistence
    ) throws -> [ProjectSnapshot] {
        do {
            return try persistence.loadProjects()
        } catch {
            persistence.rollback()
            if let error = error as? OrderingPersistenceError {
                throw error
            }
            throw OrderingPersistenceError.loadFailed(
                error.localizedDescription
            )
        }
    }

    private static func ordered(
        _ projects: [ProjectSnapshot]
    ) -> [ProjectSnapshot] {
        projects.sorted {
            if $0.order != $1.order {
                return $0.order < $1.order
            }
            return $0.id.uuidString < $1.id.uuidString
        }
    }

    private static func orderingPersistenceError(
        _ error: Error,
        applying: Bool
    ) -> OrderingPersistenceError {
        if let error = error as? OrderingPersistenceError {
            return error
        }
        return applying
            ? .applyFailed(error.localizedDescription)
            : .saveFailed(error.localizedDescription)
    }
}
