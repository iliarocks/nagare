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

    @Test func newProjectDefaultsToNormalPriority() {
        let project = Project(title: "Project", order: "i")

        #expect(project.priority == .normal)
    }

    @Test func prioritiesExposeOnlyAdjacentAvailableMoves() {
        #expect(ProjectPriority.high.higher == nil)
        #expect(ProjectPriority.high.lower == .normal)
        #expect(ProjectPriority.normal.higher == .high)
        #expect(ProjectPriority.normal.lower == .low)
        #expect(ProjectPriority.low.higher == .normal)
        #expect(ProjectPriority.low.lower == nil)
    }

    @Test func movingProjectBetweenTiersOnlyChangesProjectPlacement() throws {
        let context = try makeContext()
        let priority = Project(title: "Priority", isPriority: true, order: "i")
        let background = Project(title: "Background", order: "9")
        context.insert(priority); context.insert(background)
        let todo = insertTodo("Todo", order: "r", projectOrder: "f", project: background, into: context)
        try context.save()
        let originalDate = todo.scheduledDate
        let snapshot = try orderingCommands(in: context).moveProjects(
            [background.id], toPriority: .high, before: priority.id, at: date(day: 1)
        )
        let moved = try #require(snapshot.projectsByID[background.id])
        #expect(moved.priority == .high)
        #expect(moved.order < snapshot.projectsByID[priority.id]!.order)
        #expect(snapshot.todosByID[todo.id]?.order == "r")
        #expect(snapshot.todosByID[todo.id]?.projectOrder == "f")
        #expect(snapshot.todosByID[todo.id]?.scheduledDate == originalDate)
    }

    @Test func displayedProjectOrderSavesWithinOneTier() throws {
        let context = try makeContext()
        let priority = Project(title: "Priority", isPriority: true, order: "9")
        let first = Project(title: "First", order: "9")
        let second = Project(title: "Second", order: "i")
        [priority, first, second].forEach { context.insert($0) }
        try context.save()
        let snapshot = try orderingCommands(in: context).reorderProjects(
            [second.id, first.id], priority: .normal, at: date(day: 1)
        )
        #expect(snapshot.projectsByID[second.id]!.order < snapshot.projectsByID[first.id]!.order)
        #expect(snapshot.projectsByID[priority.id]?.order == "9")
        #expect(snapshot.projectsByID[priority.id]?.priority == .high)
    }

    @Test func movingProjectAcrossNormalAndLowRespectsDropPosition() throws {
        let context = try makeContext()
        let normal = Project(title: "Normal", order: "a")
        let firstLow = Project(title: "First low", priority: .low, order: "a")
        let secondLow = Project(title: "Second low", priority: .low, order: "b")
        [normal, firstLow, secondLow].forEach { context.insert($0) }
        try context.save()
        let commands = orderingCommands(in: context)
        let low = try commands.moveProjects([normal.id], toPriority: .low, before: secondLow.id, at: date(day: 1))
        #expect(low.projectsByID[normal.id]?.priority == .low)
        #expect(low.projectsByID[firstLow.id]!.order < low.projectsByID[normal.id]!.order)
        #expect(low.projectsByID[normal.id]!.order < low.projectsByID[secondLow.id]!.order)
        let restored = try commands.moveProjects([normal.id], toPriority: .normal, before: nil, at: date(day: 1))
        #expect(restored.projectsByID[normal.id]?.priority == .normal)
    }

    @Test func projectItemMoveDoesNotChangeDateOrderOrSchedule() throws {
        let context = try makeContext()
        let project = Project(title: "Project", order: "i")
        context.insert(project)
        let first = insertTodo("First", order: "9", projectOrder: "9", project: project, into: context)
        let second = insertTodo("Second", order: "i", projectOrder: "i", project: project, into: context)
        let originalDate = second.scheduledDate
        try context.save()
        let snapshot = try orderingCommands(in: context).moveProjectItems(
            [second.id], before: first.id, projectID: project.id, at: date(day: 1)
        )
        #expect(snapshot.todosByID[second.id]!.projectOrder! < snapshot.todosByID[first.id]!.projectOrder!)
        #expect(snapshot.todosByID[first.id]?.order == "9")
        #expect(snapshot.todosByID[second.id]?.order == "i")
        #expect(snapshot.todosByID[second.id]?.scheduledDate == originalDate)
    }

    @Test func dateMoveDoesNotChangeProjectOrder() throws {
        let context = try makeContext()
        let project = Project(title: "Project", order: "i")
        context.insert(project)
        let first = insertTodo("First", order: "9", projectOrder: "9", project: project, into: context)
        let second = insertTodo("Second", order: "i", projectOrder: "i", project: project, into: context)
        try context.save()
        let snapshot = try orderingCommands(in: context).moveItems(
            [second.id], to: first.scheduledDate, before: first.id, calendar: calendar, at: date(day: 1)
        )
        #expect(snapshot.todosByID[second.id]!.order < snapshot.todosByID[first.id]!.order)
        #expect(snapshot.todosByID[first.id]?.projectOrder == "9")
        #expect(snapshot.todosByID[second.id]?.projectOrder == "i")
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
            isStoredInMemoryOnly: true,
            cloudKitDatabase: .none
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
