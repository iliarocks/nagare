import Foundation
import SwiftData
import Testing
@testable import Nagare

@MainActor
struct ProjectTests {
    private let calendar: Calendar = {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        return calendar
    }()

    @Test func newProjectDefaultsToBackground() {
        let project = Project(title: "Project", order: "i")

        #expect(project.isPriority == false)
    }

    @Test func movingProjectBetweenTiersOnlyChangesProjectPlacement() throws {
        let context = try makeContext()
        let firstPriority = Project(
            title: "First priority",
            isPriority: true,
            order: "9"
        )
        let secondPriority = Project(
            title: "Second priority",
            isPriority: true,
            order: "i"
        )
        let background = Project(title: "Background", order: "9")
        context.insert(firstPriority)
        context.insert(secondPriority)
        context.insert(background)

        let todo = Todo(
            title: "Todo",
            scheduledDate: date(day: 1),
            order: "r",
            projectOrder: "f"
        )
        todo.project = background
        context.insert(todo)
        try context.save()
        let originalScheduledDate = todo.scheduledDate

        try ProjectOrdering.move(
            [background.id],
            toPriority: true,
            before: firstPriority.id,
            in: context
        )

        #expect(background.isPriority)
        #expect(
            Project.ordered([firstPriority, secondPriority, background])
                .filter(\.isPriority)
                .map(\.title) == [
                    "Background",
                    "First priority",
                    "Second priority"
                ]
        )
        #expect(todo.order == "r")
        #expect(todo.projectOrder == "f")
        #expect(todo.scheduledDate == originalScheduledDate)
    }

    @Test func displayedProjectOrderSavesWithinOneTier() throws {
        let context = try makeContext()
        let priority = Project(
            title: "Priority",
            isPriority: true,
            order: "9"
        )
        let first = Project(title: "First", order: "9")
        let second = Project(title: "Second", order: "i")
        context.insert(priority)
        context.insert(first)
        context.insert(second)
        try context.save()

        try ProjectOrdering.saveDisplayedOrder(
            [second.id, first.id],
            isPriority: false,
            in: context
        )

        #expect(Project.ordered([first, second]).map(\.id) == [second.id, first.id])
        #expect(priority.order == "9")
        #expect(priority.isPriority)
    }

    @Test func projectItemMoveDoesNotChangeDateOrderOrSchedule() throws {
        let context = try makeContext()
        let project = Project(title: "Project", order: "i")
        context.insert(project)
        let first = insertTodo(
            "First",
            order: "9",
            projectOrder: "9",
            project: project,
            into: context
        )
        let second = insertTodo(
            "Second",
            order: "i",
            projectOrder: "i",
            project: project,
            into: context
        )
        let originalDate = second.scheduledDate
        try context.save()

        try ProjectItemOrdering.move(
            [.todo(second.id)],
            before: .todo(first.id),
            in: project,
            context: context
        )

        #expect(second.projectOrder! < first.projectOrder!)
        #expect(first.order == "9")
        #expect(second.order == "i")
        #expect(second.scheduledDate == originalDate)
    }

    @Test func dateMoveDoesNotChangeProjectOrder() throws {
        let context = try makeContext()
        let project = Project(title: "Project", order: "i")
        context.insert(project)
        let first = insertTodo(
            "First",
            order: "9",
            projectOrder: "9",
            project: project,
            into: context
        )
        let second = insertTodo(
            "Second",
            order: "i",
            projectOrder: "i",
            project: project,
            into: context
        )
        try context.save()

        try ItemOrdering.move(
            [.todo(second.id)],
            to: first.scheduledDate,
            before: .todo(first.id),
            in: context,
            calendar: calendar
        )

        #expect(second.order < first.order)
        #expect(first.projectOrder == "9")
        #expect(second.projectOrder == "i")
    }

    @Test func recurrenceAssignmentAndAdvancementStayInProject() throws {
        let context = try makeContext()
        let firstProject = Project(title: "First", order: "9")
        let secondProject = Project(title: "Second", order: "i")
        context.insert(firstProject)
        context.insert(secondProject)
        let todo = insertTodo(
            "Repeat",
            order: "9",
            projectOrder: nil,
            project: nil,
            into: context
        )
        let rule = try RecurrenceRule.relative(every: 1, unit: .day)
        let template = try RecurrencePersistence.createTemplate(
            for: todo,
            rule: rule,
            in: context
        )

        try ProjectMembership.assign(
            template,
            to: firstProject,
            in: context
        )
        let firstProjectOrder = todo.projectOrder
        #expect(todo.project?.id == firstProject.id)
        #expect(template.project?.id == firstProject.id)
        #expect(firstProjectOrder != nil)

        try ProjectMembership.assign(
            template,
            to: secondProject,
            in: context
        )
        #expect(todo.project?.id == secondProject.id)
        #expect(template.project?.id == secondProject.id)

        let next = try #require(
            try RecurrencePersistence.complete(
                todo,
                at: date(day: 2),
                in: context,
                calendar: calendar
            )
        )
        #expect(next.project?.id == secondProject.id)
        #expect(next.projectOrder == todo.projectOrder)
        #expect(template.project?.id == secondProject.id)
    }

    @Test func deletingProjectDetachesButPreservesItemsAndRepeat() throws {
        let context = try makeContext()
        let project = Project(title: "Project", order: "i")
        context.insert(project)
        let todo = insertTodo(
            "Repeat",
            order: "9",
            projectOrder: "i",
            project: project,
            into: context
        )
        let rule = try RecurrenceRule.relative(every: 1, unit: .day)
        let template = try RecurrencePersistence.createTemplate(
            for: todo,
            rule: rule,
            in: context
        )
        try context.save()

        try ProjectPersistence.delete(project, in: context)

        #expect(try context.fetch(FetchDescriptor<Project>()).isEmpty)
        #expect(try context.fetch(FetchDescriptor<Todo>()).count == 1)
        #expect(
            try context.fetch(FetchDescriptor<RecurrenceTemplate>()).count == 1
        )
        #expect(todo.project == nil)
        #expect(todo.projectOrder == nil)
        #expect(template.project == nil)
        #expect(todo.recurrenceTemplate?.id == template.id)
    }

    private func makeContext() throws -> ModelContext {
        let configuration = ModelConfiguration(
            for: Project.self,
            Todo.self,
            Event.self,
            RecurrenceTemplate.self,
            isStoredInMemoryOnly: true
        )
        let container = try ModelContainer(
            for: Project.self,
            Todo.self,
            Event.self,
            RecurrenceTemplate.self,
            configurations: configuration
        )
        return ModelContext(container)
    }

    @discardableResult
    private func insertTodo(
        _ title: String,
        order: String,
        projectOrder: String?,
        project: Project?,
        into context: ModelContext
    ) -> Todo {
        let todo = Todo(
            title: title,
            scheduledDate: date(day: 1),
            order: order,
            projectOrder: projectOrder,
            calendar: calendar
        )
        todo.project = project
        context.insert(todo)
        return todo
    }

    private func date(day: Int) -> Date {
        calendar.date(
            from: DateComponents(year: 2026, month: 8, day: day)
        )!
    }
}
