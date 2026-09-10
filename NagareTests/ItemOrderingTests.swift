import Foundation
import SwiftData
import Testing
@testable import Nagare

@MainActor
struct ItemOrderingTests {
    private let calendar: Calendar = {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = .autoupdatingCurrent
        return calendar
    }()

    @Test func persistsMoveBeforeFirstItem() throws {
        let context = try makeContext()
        let day = date(day: 1)
        let first = insertTodo("First", order: "9", day: day, into: context)
        _ = insertTodo("Second", order: "i", day: day, into: context)
        let third = insertTodo("Third", order: "r", day: day, into: context)
        try context.save()

        _ = try orderingCommands(in: context).moveItems(
            [third.id],
            to: day,
            before: first.id,
            calendar: calendar,
            at: date(day: 1)
        )

        #expect(try orderedTodoTitles(on: day, in: context) == ["Third", "First", "Second"])

        let verificationContext = ModelContext(context.container)
        #expect(
            try orderedTodoTitles(on: day, in: verificationContext)
                == ["Third", "First", "Second"]
        )
    }

    @Test func persistsMoveToEnd() throws {
        let context = try makeContext()
        let day = date(day: 1)
        let first = insertTodo("First", order: "9", day: day, into: context)
        _ = insertTodo("Second", order: "i", day: day, into: context)
        _ = insertTodo("Third", order: "r", day: day, into: context)
        try context.save()

        _ = try orderingCommands(in: context).moveItems(
            [first.id],
            to: day,
            before: nil,
            calendar: calendar,
            at: date(day: 1)
        )

        #expect(try orderedTodoTitles(on: day, in: context) == ["Second", "Third", "First"])
    }

    @Test func preservesSourceOrderForMultiItemMove() throws {
        let context = try makeContext()
        let day = date(day: 1)
        let first = insertTodo("First", order: "9", day: day, into: context)
        let second = insertTodo("Second", order: "i", day: day, into: context)
        let third = insertTodo("Third", order: "r", day: day, into: context)
        _ = insertTodo("Fourth", order: "v", day: day, into: context)
        try context.save()

        _ = try orderingCommands(in: context).moveItems(
            [third.id, first.id],
            to: day,
            before: second.id,
            calendar: calendar,
            at: date(day: 1)
        )

        #expect(
            try orderedTodoTitles(on: day, in: context)
                == ["Third", "First", "Second", "Fourth"]
        )
    }

    @Test func rebalancesDestinationWhenNoFractionalKeyExists() throws {
        let context = try makeContext()
        let day = date(day: 1)
        _ = insertTodo("First", order: "a", day: day, into: context)
        let second = insertTodo("Second", order: "a0", day: day, into: context)
        let third = insertTodo("Third", order: "z", day: day, into: context)
        try context.save()

        _ = try orderingCommands(in: context).moveItems(
            [third.id],
            to: day,
            before: second.id,
            calendar: calendar,
            at: date(day: 1)
        )

        let ordered = try orderedTodos(on: day, in: context)
        #expect(ordered.map(\.title) == ["First", "Third", "Second"])
        #expect(ordered.allSatisfy { $0.order.count == 12 })
        #expect(ordered.map(\.order) == ordered.map(\.order).sorted())
    }

    @Test func movesItemAcrossDaysAndPersistsItsDate() throws {
        let context = try makeContext()
        let firstDay = date(day: 1)
        let secondDay = date(day: 2)
        _ = insertTodo("First", order: "9", day: firstDay, into: context)
        let second = insertTodo("Second", order: "i", day: firstDay, into: context)
        let moving = insertTodo("Moving", order: "r", day: secondDay, into: context)
        try context.save()

        _ = try orderingCommands(in: context).moveItems(
            [moving.id],
            to: firstDay,
            before: second.id,
            calendar: calendar,
            at: date(day: 1)
        )

        #expect(try orderedTodoTitles(on: firstDay, in: context) == ["First", "Moving", "Second"])
        let moved = try #require(try orderingRepository(in: context).load().todosByID[moving.id])
        #expect(calendar.isDate(moved.scheduledDate, inSameDayAs: firstDay))
    }

    @Test func movesTimedTodoAcrossDaysWithoutChangingItsTimeOrDuration() throws {
        let context = try makeContext()
        let firstDay = date(day: 1)
        let secondDay = date(day: 2)
        let destination = insertTodo(
            "Destination",
            order: "i",
            day: firstDay,
            into: context
        )
        let start = try #require(
            calendar.date(
                bySettingHour: 9,
                minute: 30,
                second: 0,
                of: secondDay
            )
        )
        let end = start.addingTimeInterval(90 * 60)
        let moving = Todo(
            title: "Moving Timed Todo",
            scheduledDate: start,
            includesTime: true,
            endDate: end,
            order: "r"
        )
        context.insert(moving)
        try context.save()

        _ = try orderingCommands(in: context).moveItems(
            [moving.id],
            to: firstDay,
            before: destination.id,
            calendar: calendar,
            at: date(day: 1)
        )

        let moved = try #require(try orderingRepository(in: context).load().todosByID[moving.id])
        #expect(calendar.isDate(moved.scheduledDate, inSameDayAs: firstDay))
        #expect(
            calendar.dateComponents(
                [.hour, .minute],
                from: moved.scheduledDate
            ) == DateComponents(hour: 9, minute: 30)
        )
        #expect(
            moved.endDate?.timeIntervalSince(moved.scheduledDate)
                == TimeInterval(90 * 60)
        )

        let verificationContext = ModelContext(context.container)
        let persistedTodos = try verificationContext.fetch(
            FetchDescriptor<Todo>()
        )
        let persisted = try #require(
            persistedTodos.first(where: { $0.id == moving.id })
        )
        #expect(
            calendar.isDate(persisted.scheduledDate, inSameDayAs: firstDay)
        )
        #expect(
            persisted.endDate?.timeIntervalSince(persisted.scheduledDate)
                == TimeInterval(90 * 60)
        )
    }

    @Test func reportsDuplicateSourcesInsteadOfSilentlyReturning() throws {
        let context = try makeContext()
        let day = date(day: 1)
        let todo = insertTodo("Todo", order: "i", day: day, into: context)
        try context.save()

        let error = captureMoveError {
            try orderingCommands(in: context).moveItems(
                [todo.id, todo.id],
                to: day,
                before: nil,
                calendar: calendar,
                at: date(day: 1)
            )
        }

        #expect(error == .duplicateSource)
    }

    @Test func reportsMissingSourceInsteadOfSilentlyReturning() throws {
        let context = try makeContext()
        let day = date(day: 1)

        let error = captureMoveError {
            try orderingCommands(in: context).moveItems(
                [UUID()],
                to: day,
                before: nil,
                calendar: calendar,
                at: date(day: 1)
            )
        }

        #expect(error == .missingSource)
    }

    @Test func reportsMissingDestinationInsteadOfAppending() throws {
        let context = try makeContext()
        let day = date(day: 1)
        let todo = insertTodo("Todo", order: "i", day: day, into: context)
        try context.save()

        let error = captureMoveError {
            try orderingCommands(in: context).moveItems(
                [todo.id],
                to: day,
                before: UUID(),
                calendar: calendar,
                at: date(day: 1)
            )
        }

        #expect(error == .missingDestination)
    }

    @Test func reportsDestinationThatOverlapsMovingItems() throws {
        let context = try makeContext()
        let day = date(day: 1)
        let todo = insertTodo("Todo", order: "i", day: day, into: context)
        try context.save()

        let error = captureMoveError {
            try orderingCommands(in: context).moveItems(
                [todo.id],
                to: day,
                before: todo.id,
                calendar: calendar,
                at: date(day: 1)
            )
        }

        #expect(error == .destinationIsMovingValue)
    }

    @Test func repairsInvalidStoredKeyWhenMoving() throws {
        let context = try makeContext()
        let day = date(day: 1)
        let invalid = insertTodo("Invalid", order: "UPPERCASE", day: day, into: context)
        try context.save()
        let snapshot = try orderingCommands(in: context).moveItems(
            [invalid.id], to: day, before: nil, calendar: calendar, at: day
        )
        let moved = try #require(snapshot.todosByID[invalid.id])
        #expect(FractionalIndex.isValid(moved.order))
        #expect(moved.title == "Invalid")
    }

    @Test func unrelatedInvalidKeyDoesNotBlockDestinationCollection() throws {
        let context = try makeContext()
        let firstDay = date(day: 1)
        let secondDay = date(day: 2)
        let first = insertTodo("First", order: "9", day: firstDay, into: context)
        let second = insertTodo("Second", order: "i", day: firstDay, into: context)
        _ = insertTodo("Unrelated", order: "INVALID", day: secondDay, into: context)
        try context.save()

        _ = try orderingCommands(in: context).moveItems(
            [second.id],
            to: firstDay,
            before: first.id,
            calendar: calendar,
            at: date(day: 1)
        )

        #expect(try orderedTodoTitles(on: firstDay, in: context) == ["Second", "First"])
    }

    @Test func recognizesVerifiedNoOp() throws {
        let context = try makeContext()
        let day = date(day: 1)
        _ = insertTodo("First", order: "9", day: day, into: context)
        let second = insertTodo("Second", order: "i", day: day, into: context)
        let third = insertTodo("Third", order: "r", day: day, into: context)
        try context.save()

        _ = try orderingCommands(in: context).moveItems(
            [second.id],
            to: day,
            before: third.id,
            calendar: calendar,
            at: date(day: 1)
        )

        #expect(try orderedTodoTitles(on: day, in: context) == ["First", "Second", "Third"])
    }

    @Test func persistsTheExactDisplayedOrderUsedByTheDragUI() throws {
        let context = try makeContext()
        let day = date(day: 1)
        let first = insertTodo("First", order: "9", day: day, into: context)
        let second = insertTodo("Second", order: "i", day: day, into: context)
        let third = insertTodo("Third", order: "r", day: day, into: context)
        try context.save()

        let current = try orderingRepository(in: context).load()
        let plan = try OrderingPlanner.displayedOrder(
            [third.id, first.id, second.id],
            contains: current.canonicalTodos.map { OrderingPlanner.Entry(id: $0.id, order: $0.order) }
        )
        _ = try orderingCommands(in: context).saveItemOrdering(
            plan.assignments.map { ItemOrderingChange(id: $0.id, order: $0.order) }, at: day
        )

        let verificationContext = ModelContext(context.container)
        #expect(
            try orderedTodoTitles(on: day, in: verificationContext)
                == ["Third", "First", "Second"]
        )
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
        day: Date,
        into context: ModelContext
    ) -> Todo {
        let todo = Todo(title: title, scheduledDate: day, order: order)
        context.insert(todo)
        return todo
    }

    private func orderedTodoTitles(
        on day: Date,
        in context: ModelContext
    ) throws -> [String] {
        try orderedTodos(on: day, in: context).map(\.title)
    }

    private func orderedTodos(
        on day: Date,
        in context: ModelContext
    ) throws -> [Todo] {
        let todos = try ModelContext(context.container).fetch(FetchDescriptor<Todo>()).filter {
            calendar.isDate($0.scheduledDate, inSameDayAs: day)
        }
        return Todo.ordered(todos)
    }

    private func date(day: Int) -> Date {
        calendar.date(
            from: DateComponents(year: 2026, month: 7, day: day, hour: 12)
        )!
    }

    private func captureMoveError(
        _ operation: () throws -> NagareDataSnapshot
    ) -> OrderingPlanner.PlanningError? {
        do {
            _ = try operation()
            Issue.record("Expected the move to throw")
            return nil
        } catch let error as OrderingPlanner.PlanningError {
            return error
        } catch {
            Issue.record("Unexpected error type: \(error)")
            return nil
        }
    }
}
