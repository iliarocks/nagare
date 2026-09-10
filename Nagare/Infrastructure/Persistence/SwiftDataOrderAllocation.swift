import Foundation
import SwiftData

/// Allocates positions inside an existing persistence transaction. The caller
/// owns saving/rollback; pure ordering policy stays in OrderingPlanner.
@MainActor
enum SwiftDataOrderAllocation {
    static func nextItemOrder(in context: ModelContext) throws -> String {
        let todos = Todo.ordered(try context.fetch(FetchDescriptor<Todo>()))
        let plan = try OrderingPlanner.nextOrder(after: todos.map {
            OrderingPlanner.Entry(id: $0.id, order: $0.order)
        })
        for repair in plan.repairs {
            for todo in todos where todo.id == repair.id { todo.applyOrder(repair.order) }
        }
        return plan.order
    }

    static func nextProjectItemOrder(in project: Project, context: ModelContext) throws -> String {
        let todos = try context.fetch(FetchDescriptor<Todo>()).filter {
            $0.project?.id == project.id && $0.completedAt == nil
        }.sorted {
            if $0.projectOrder != $1.projectOrder { return ($0.projectOrder ?? "") < ($1.projectOrder ?? "") }
            return $0.id.uuidString < $1.id.uuidString
        }
        let entries = try todos.map { todo in
            guard let order = todo.projectOrder else { throw OrderingPlanner.PlanningError.invalidOrderKey }
            return OrderingPlanner.Entry(id: todo.id, order: order)
        }
        let plan = try OrderingPlanner.nextOrder(after: entries)
        for repair in plan.repairs {
            for todo in todos where todo.id == repair.id { todo.applyProjectOrder(repair.order) }
        }
        return plan.order
    }
}
