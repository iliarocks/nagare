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

        let outcome = try ItemOrdering.move(
            [.todo(third.id)],
            to: day,
            before: .todo(first.id),
            in: context,
            calendar: calendar
        )

        #expect(outcome == .saved)
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

        try ItemOrdering.move(
            [.todo(first.id)],
            to: day,
            before: nil,
            in: context,
            calendar: calendar
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

        try ItemOrdering.move(
            [.todo(third.id), .todo(first.id)],
            to: day,
            before: .todo(second.id),
            in: context,
            calendar: calendar
        )

        #expect(
            try orderedTodoTitles(on: day, in: context)
                == ["Third", "First", "Second", "Fourth"]
        )
    }

    @Test func rebalancesDestinationWhenNoFractionalKeyExists() throws {
        let context = try makeContext()
        let day = date(day: 1)
        let first = insertTodo("First", order: "a", day: day, into: context)
        let second = insertTodo("Second", order: "a0", day: day, into: context)
        let third = insertTodo("Third", order: "z", day: day, into: context)
        try context.save()

        try ItemOrdering.move(
            [.todo(third.id)],
            to: day,
            before: .todo(second.id),
            in: context,
            calendar: calendar
        )

        let ordered = try orderedTodos(on: day, in: context)
        #expect(ordered.map(\.title) == ["First", "Third", "Second"])
        #expect(ordered.allSatisfy { $0.order.count == 12 })
        #expect(ordered.map(\.order) == ordered.map(\.order).sorted())
        #expect(first.order < third.order && third.order < second.order)
    }

    @Test func movesItemAcrossDaysAndPersistsItsDate() throws {
        let context = try makeContext()
        let firstDay = date(day: 1)
        let secondDay = date(day: 2)
        _ = insertTodo("First", order: "9", day: firstDay, into: context)
        let second = insertTodo("Second", order: "i", day: firstDay, into: context)
        let moving = insertTodo("Moving", order: "r", day: secondDay, into: context)
        try context.save()

        try ItemOrdering.move(
            [.todo(moving.id)],
            to: firstDay,
            before: .todo(second.id),
            in: context,
            calendar: calendar
        )

        #expect(try orderedTodoTitles(on: firstDay, in: context) == ["First", "Moving", "Second"])
        #expect(calendar.isDate(moving.scheduledDate, inSameDayAs: firstDay))
    }

    @Test func reportsDuplicateSourcesInsteadOfSilentlyReturning() throws {
        let context = try makeContext()
        let day = date(day: 1)
        let todo = insertTodo("Todo", order: "i", day: day, into: context)
        try context.save()

        let error = captureMoveError {
            try ItemOrdering.move(
                [.todo(todo.id), .todo(todo.id)],
                to: day,
                before: nil,
                in: context,
                calendar: calendar
            )
        }

        #expect(error?.code == "ORDER-001")
    }

    @Test func reportsMissingSourceInsteadOfSilentlyReturning() throws {
        let context = try makeContext()
        let day = date(day: 1)

        let error = captureMoveError {
            try ItemOrdering.move(
                [.todo(UUID())],
                to: day,
                before: nil,
                in: context,
                calendar: calendar
            )
        }

        #expect(error?.code == "ORDER-002")
    }

    @Test func reportsMissingDestinationInsteadOfAppending() throws {
        let context = try makeContext()
        let day = date(day: 1)
        let todo = insertTodo("Todo", order: "i", day: day, into: context)
        try context.save()

        let error = captureMoveError {
            try ItemOrdering.move(
                [.todo(todo.id)],
                to: day,
                before: .todo(UUID()),
                in: context,
                calendar: calendar
            )
        }

        #expect(error?.code == "ORDER-003")
    }

    @Test func reportsDestinationThatOverlapsMovingItems() throws {
        let context = try makeContext()
        let day = date(day: 1)
        let todo = insertTodo("Todo", order: "i", day: day, into: context)
        try context.save()

        let error = captureMoveError {
            try ItemOrdering.move(
                [.todo(todo.id)],
                to: day,
                before: .todo(todo.id),
                in: context,
                calendar: calendar
            )
        }

        #expect(error?.code == "ORDER-004")
        #expect(error?.localizedDescription.contains("ORDER-004") == true)
    }

    @Test func reportsInvalidStoredKeyBeforeApplyingMove() throws {
        let context = try makeContext()
        let day = date(day: 1)
        let invalid = insertTodo("Invalid", order: "UPPERCASE", day: day, into: context)
        try context.save()

        let error = captureMoveError {
            try ItemOrdering.move(
                [.todo(invalid.id)],
                to: day,
                before: nil,
                in: context,
                calendar: calendar
            )
        }

        #expect(error?.code == "ORDER-005")
    }

    @Test func unrelatedInvalidKeyDoesNotBlockDestinationCollection() throws {
        let context = try makeContext()
        let firstDay = date(day: 1)
        let secondDay = date(day: 2)
        let first = insertTodo("First", order: "9", day: firstDay, into: context)
        let second = insertTodo("Second", order: "i", day: firstDay, into: context)
        _ = insertTodo("Unrelated", order: "INVALID", day: secondDay, into: context)
        try context.save()

        let outcome = try ItemOrdering.move(
            [.todo(second.id)],
            to: firstDay,
            before: .todo(first.id),
            in: context,
            calendar: calendar
        )

        #expect(outcome == .saved)
        #expect(try orderedTodoTitles(on: firstDay, in: context) == ["Second", "First"])
    }

    @Test func recognizesVerifiedNoOp() throws {
        let context = try makeContext()
        let day = date(day: 1)
        _ = insertTodo("First", order: "9", day: day, into: context)
        let second = insertTodo("Second", order: "i", day: day, into: context)
        let third = insertTodo("Third", order: "r", day: day, into: context)
        try context.save()

        let outcome = try ItemOrdering.move(
            [.todo(second.id)],
            to: day,
            before: .todo(third.id),
            in: context,
            calendar: calendar
        )

        #expect(outcome == .noChange)
        #expect(try orderedTodoTitles(on: day, in: context) == ["First", "Second", "Third"])
    }

    @Test func persistsTheExactDisplayedOrderUsedByTheDragUI() throws {
        let context = try makeContext()
        let day = date(day: 1)
        let first = insertTodo("First", order: "9", day: day, into: context)
        let second = insertTodo("Second", order: "i", day: day, into: context)
        let third = insertTodo("Third", order: "r", day: day, into: context)
        try context.save()

        try ItemOrdering.saveDisplayedOrder(
            [.todo(third.id), .todo(first.id), .todo(second.id)],
            on: day,
            in: context,
            calendar: calendar
        )

        let verificationContext = ModelContext(context.container)
        #expect(
            try orderedTodoTitles(on: day, in: verificationContext)
                == ["Third", "First", "Second"]
        )
    }

    private func makeContext() throws -> ModelContext {
        let configuration = ModelConfiguration(
            for: Todo.self,
            Event.self,
            isStoredInMemoryOnly: true
        )
        let container = try ModelContainer(
            for: Todo.self,
            Event.self,
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
        let todos = try context.fetch(FetchDescriptor<Todo>()).filter {
            calendar.isDate($0.scheduledDate, inSameDayAs: day)
        }
        return Item.ordered(todos: todos, events: []).compactMap { item in
            guard case .todo(let todo) = item else { return nil }
            return todo
        }
    }

    private func date(day: Int) -> Date {
        calendar.date(
            from: DateComponents(year: 2026, month: 7, day: day, hour: 12)
        )!
    }

    private func captureMoveError(
        _ operation: () throws -> ItemOrdering.MoveOutcome
    ) -> ItemOrdering.MoveError? {
        do {
            _ = try operation()
            Issue.record("Expected the move to throw")
            return nil
        } catch let error as ItemOrdering.MoveError {
            return error
        } catch {
            Issue.record("Unexpected error type: \(error)")
            return nil
        }
    }
}
