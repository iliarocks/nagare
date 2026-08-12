import Foundation
import SwiftData

/// Razor-thin SwiftData adapter. It translates records to immutable snapshots
/// and applies explicit changes; it contains no ordering decisions.
@MainActor
final class SwiftDataOrderingAdapter:
    ItemOrderingPersistence,
    ProjectOrderingPersistence
{
    private let context: ModelContext
    private var itemsByID: [ItemID: Item] = [:]
    private var projectsByID: [UUID: Project] = [:]

    init(context: ModelContext) {
        self.context = context
    }

    func loadItems() throws -> [ItemSnapshot] {
        do {
            let items = try context.fetch(FetchDescriptor<Todo>()).map(Item.todo)
                + context.fetch(FetchDescriptor<Event>()).map(Item.event)
            itemsByID = Dictionary(
                uniqueKeysWithValues: items.map { ($0.id, $0) }
            )
            return items.map(\.snapshot)
        } catch {
            throw OrderingPersistenceError.loadFailed(
                error.localizedDescription
            )
        }
    }

    func loadProjects() throws -> [ProjectSnapshot] {
        do {
            let projects = try context.fetch(FetchDescriptor<Project>())
            projectsByID = Dictionary(
                uniqueKeysWithValues: projects.map { ($0.id, $0) }
            )
            return projects.map {
                ProjectSnapshot(
                    id: $0.id,
                    isPriority: $0.isPriority,
                    order: $0.order
                )
            }
        } catch {
            throw OrderingPersistenceError.loadFailed(
                error.localizedDescription
            )
        }
    }

    func apply(_ changes: [ItemOrderingChange]) throws {
        for change in changes {
            guard let item = itemsByID[change.id] else {
                throw OrderingPersistenceError.applyFailed(
                    "The item no longer exists."
                )
            }
            if let order = change.order {
                item.applyOrder(order)
            }
            if let scheduledDate = change.scheduledDate {
                item.applySchedule(
                    scheduledDate: scheduledDate,
                    endDate: change.endDate
                )
            }
        }
    }

    func applyProjectOrder(
        _ changes: [ProjectItemOrderingChange]
    ) throws {
        for change in changes {
            guard let item = itemsByID[change.id] else {
                throw OrderingPersistenceError.applyFailed(
                    "The project item no longer exists."
                )
            }
            item.applyProjectOrder(change.projectOrder)
        }
    }

    func apply(_ changes: [ProjectOrderingChange]) throws {
        for change in changes {
            guard let project = projectsByID[change.id] else {
                throw OrderingPersistenceError.applyFailed(
                    "The project no longer exists."
                )
            }
            if let order = change.order {
                project.order = order
            }
            if let isPriority = change.isPriority {
                project.isPriority = isPriority
            }
        }
    }

    func save() throws {
        do {
            try SwiftDataTransaction.save(context)
        } catch {
            throw OrderingPersistenceError.saveFailed(
                error.localizedDescription
            )
        }
    }

    func rollback() {
        context.rollback()
    }
}
