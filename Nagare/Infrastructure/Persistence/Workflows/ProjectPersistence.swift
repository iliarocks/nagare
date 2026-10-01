import Foundation
import SwiftData

enum ProjectPersistence {
    @MainActor
    @discardableResult
    static func migrateLegacyPriorities(in projects: [Project]) throws -> Bool {
        // A partial import can still contain duplicate semantic IDs. Let sync
        // reconciliation choose its survivors before changing their ordering.
        guard Set(projects.map(\.id)).count == projects.count else { return false }
        let changes = try ProjectPriorityMigration.orderingChanges(
            for: projects.map {
                ProjectPriorityMigration.Entry(
                    id: $0.id,
                    priority: $0.priority,
                    isLegacyLow: $0.priorityRawValue == 0,
                    order: $0.order
                )
            }
        )
        guard !changes.isEmpty else { return false }
        let projectsByID = Dictionary(uniqueKeysWithValues: projects.map { ($0.id, $0) })
        for change in changes {
            guard let project = projectsByID[change.id] else { continue }
            if let order = change.order { project.order = order }
            if let priority = change.priority { project.priority = priority }
        }
        return true
    }

    enum PersistenceError: LocalizedError {
        case saveFailed(String)

        var errorDescription: String? {
            switch self {
            case .saveFailed(let message):
                "Nagare couldn't delete the project. \(message) (PROJECT-DELETE-001)"
            }
        }
    }

    @MainActor
    static func delete(
        _ project: Project,
        at modificationDate: Date = .now,
        in context: ModelContext
    ) throws {
        for todo in project.todos {
            todo.project = nil
            todo.projectOrder = nil
        }
        for event in project.events {
            event.project = nil
            event.projectOrder = nil
        }
        for template in project.recurrenceTemplates {
            template.project = nil
        }
        context.delete(project)

        do {
            try SwiftDataTransaction.save(context, at: modificationDate)
        } catch {
            context.rollback()
            throw PersistenceError.saveFailed(error.localizedDescription)
        }
    }
}
