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
        #expect(ProjectPriority.allCases == [.normal, .high])
        #expect(ProjectPriority.displayOrder == [.high, .normal])
        #expect(ProjectPriority.high.higher == nil)
        #expect(ProjectPriority.high.lower == .normal)
        #expect(ProjectPriority.normal.higher == .high)
        #expect(ProjectPriority.normal.lower == nil)
    }

    @Test func storedPriorityPreservesLegacyBooleanAndCollapsesLow() {
        #expect(ProjectPriority(storedRawValue: nil, isPriority: true) == .high)
        #expect(ProjectPriority(storedRawValue: nil, isPriority: false) == .normal)
        #expect(ProjectPriority(storedRawValue: 0, isPriority: true) == .normal)
        #expect(ProjectPriority(storedRawValue: 1, isPriority: true) == .normal)
        #expect(ProjectPriority(storedRawValue: 2, isPriority: false) == .high)
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

    @Test func deprioritizingProjectRespectsDropPosition() throws {
        let context = try makeContext()
        let priority = Project(title: "Priority", priority: .high, order: "a")
        let first = Project(title: "First", order: "a")
        let second = Project(title: "Second", order: "b")
        [priority, first, second].forEach { context.insert($0) }
        try context.save()
        let commands = orderingCommands(in: context)
        let snapshot = try commands.moveProjects(
            [priority.id], toPriority: .normal, before: second.id, at: date(day: 1)
        )
        #expect(snapshot.projectsByID[priority.id]?.priority == .normal)
        #expect(snapshot.projectsByID[first.id]!.order < snapshot.projectsByID[priority.id]!.order)
        #expect(snapshot.projectsByID[priority.id]!.order < snapshot.projectsByID[second.id]!.order)
    }

    @Test func loadingLegacyLowProjectsPreservesGroupOrderAndMetadata() throws {
        let context = try makeContext()
        let first = Project(title: "First regular", order: "m")
        let second = Project(title: "Second regular", order: "z")
        let firstLow = Project(title: "First low", order: "a")
        let secondLow = Project(title: "Second low", order: "b")
        let priority = Project(title: "Priority", priority: .high, order: "i")
        firstLow.priorityRawValue = 0
        secondLow.priorityRawValue = 0
        let projects = [secondLow, second, priority, firstLow, first]
        projects.forEach { context.insert($0) }
        let todo = insertTodo(
            "Child", order: "r", projectOrder: "f", project: firstLow, into: context
        )
        try context.save()
        let originalMetadata = Dictionary(uniqueKeysWithValues: projects.map {
            ($0.id, ($0.createdAt, $0.modifiedAt, $0.syncRecordID))
        })
        let repository = SwiftDataNagareRepository(modelContainer: context.container)

        let snapshot = try repository.load()
        let regular = snapshot.projects.filter { !$0.isPriority }.sorted {
            $0.order < $1.order
        }
        #expect(regular.map(\.id) == [first.id, second.id, firstLow.id, secondLow.id])
        #expect(snapshot.projectsByID[first.id]?.order == "m")
        #expect(snapshot.projectsByID[second.id]?.order == "z")
        #expect(snapshot.projectsByID[priority.id]?.priority == .high)
        #expect(snapshot.projectsByID[priority.id]?.order == "i")
        #expect(snapshot.todosByID[todo.id]?.projectID == firstLow.id)
        #expect(snapshot.todosByID[todo.id]?.order == "r")
        #expect(snapshot.todosByID[todo.id]?.projectOrder == "f")
        for project in snapshot.projects {
            let original = try #require(originalMetadata[project.id])
            #expect(project.createdAt == original.0)
            #expect(project.modifiedAt == original.1)
            #expect(project.syncRecordID == original.2)
        }
        let stored = try ModelContext(context.container).fetch(FetchDescriptor<Project>())
        #expect(stored.allSatisfy { $0.priorityRawValue != 0 })
        #expect(try repository.load() == snapshot)
    }

    @Test func laterLegacyPriorityImportsAppendWithoutReorderingMigratedProjects() throws {
        let context = try makeContext()
        let regular = Project(title: "Regular", order: "z")
        let earlierArrival = Project(title: "Second legacy low", order: "b")
        earlierArrival.priorityRawValue = 0
        context.insert(regular)
        context.insert(earlierArrival)
        try context.save()
        let repository = SwiftDataNagareRepository(modelContainer: context.container)
        let before = try repository.load()

        let laterArrival = Project(title: "First legacy low", order: "a")
        laterArrival.priorityRawValue = 0
        context.insert(laterArrival)
        try context.save()
        let after = try repository.load()

        for project in before.projects {
            #expect(after.projectsByID[project.id]?.order == project.order)
            #expect(after.projectsByID[project.id]?.modifiedAt == project.modifiedAt)
        }
        #expect(after.projects.sorted { $0.order < $1.order }.map(\.id)
            == [regular.id, earlierArrival.id, laterArrival.id])
        #expect(after.projects.allSatisfy { $0.priority == .normal })
    }

    @Test func normalProjectsArrivingAfterLowMigrationKeepTheirStoredPosition() throws {
        let context = try makeContext()
        let low = Project(title: "Earlier low", order: "a")
        low.priorityRawValue = 0
        context.insert(low)
        try context.save()
        let repository = SwiftDataNagareRepository(modelContainer: context.container)
        let before = try repository.load()
        let migrated = try #require(before.projectsByID[low.id])

        // A later normal record has no migration marker. Its existing key
        // remains authoritative even when it follows a former low project.
        let normal = Project(title: "Later regular", order: "z")
        context.insert(normal)
        try context.save()
        let after = try repository.load()

        #expect(after.projectsByID[low.id] == migrated)
        #expect(after.projectsByID[normal.id]?.order == "z")
        #expect(after.projectsByID[normal.id]?.modifiedAt == normal.modifiedAt)
        #expect(after.projects.sorted { $0.order < $1.order }.map(\.id)
            == [low.id, normal.id])
        #expect(after.projects.allSatisfy { $0.priority == .normal })
        #expect(try repository.load() == after)
    }

    @Test func legacyPriorityMigrationWaitsForDuplicateReconciliation() throws {
        let context = try makeContext()
        let id = UUID()
        let low = Project(id: id, title: "Old low", order: "a")
        low.priorityRawValue = 0
        let priority = Project(id: id, title: "Priority", priority: .high, order: "b")
        context.insert(low)
        context.insert(priority)
        try context.save()

        let snapshot = try SwiftDataNagareRepository(
            modelContainer: context.container
        ).load()

        #expect(snapshot.projects.count == 2)
        #expect(low.priorityRawValue == 0)
        #expect(priority.priority == .high)
        #expect(priority.order == "b")
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
