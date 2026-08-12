import Foundation
import SwiftData

enum ProjectMembership {
    enum MembershipError: LocalizedError {
        case missingCurrentOccurrence
        case saveFailed(String)

        var errorDescription: String? {
            switch self {
            case .missingCurrentOccurrence:
                "Nagare couldn't find the current repeating item. (PROJECT-MEMBERSHIP-001)"
            case .saveFailed(let message):
                "Nagare couldn't save the project assignment. \(message) (PROJECT-MEMBERSHIP-002)"
            }
        }
    }

    @MainActor
    static func assign(
        _ item: Item,
        to project: Project?,
        in context: ModelContext
    ) throws {
        do {
            try prepare(item, for: project, in: context)
            try SwiftDataTransaction.save(context)
        } catch let error as MembershipError {
            context.rollback()
            throw error
        } catch {
            context.rollback()
            throw MembershipError.saveFailed(error.localizedDescription)
        }
    }

    @MainActor
    static func assign(
        _ template: RecurrenceTemplate,
        to project: Project?,
        in context: ModelContext
    ) throws {
        let currentItem = try currentItem(for: template)
        try assign(currentItem, to: project, in: context)
    }

    @MainActor
    static func prepare(
        _ item: Item,
        for project: Project?,
        in context: ModelContext
    ) throws {
        let hasValidOrder = item.projectOrder.map(
            FractionalIndex.isValid
        ) ?? (project == nil)
        if item.project?.id == project?.id,
           hasValidOrder {
            synchronizeTemplate(for: item, with: project)
            return
        }

        let order = try project.map {
            try ProjectItemOrdering.nextOrder(in: $0, context: context)
        }
        item.applyProject(project)
        item.applyProjectOrder(order)
        synchronizeTemplate(for: item, with: project)
    }

    @MainActor
    static func prepare(
        _ template: RecurrenceTemplate,
        for project: Project?,
        in context: ModelContext
    ) throws {
        try prepare(
            currentItem(for: template),
            for: project,
            in: context
        )
    }

    private static func synchronizeTemplate(
        for item: Item,
        with project: Project?
    ) {
        switch item {
        case .todo(let todo):
            todo.recurrenceTemplate?.project = project
        case .event(let event):
            event.recurrenceTemplate?.project = project
        }
    }

    private static func currentItem(
        for template: RecurrenceTemplate
    ) throws -> Item {
        switch template.itemType {
        case .todo:
            guard let todo = template.todoOccurrences.first(where: {
                $0.id == template.currentItemID && $0.completedAt == nil
            }) else {
                throw MembershipError.missingCurrentOccurrence
            }
            return .todo(todo)
        case .event:
            guard let event = template.eventOccurrences.first(where: {
                $0.id == template.currentItemID
            }) else {
                throw MembershipError.missingCurrentOccurrence
            }
            return .event(event)
        case nil:
            throw MembershipError.missingCurrentOccurrence
        }
    }
}
