import Foundation
import SwiftData

enum ProjectPersistence {
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
            try SwiftDataTransaction.save(context)
        } catch {
            context.rollback()
            throw PersistenceError.saveFailed(error.localizedDescription)
        }
    }
}
