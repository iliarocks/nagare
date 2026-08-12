import Foundation
import SwiftData
import Testing
@testable import Nagare

@MainActor
struct RecurrencePersistenceTests {
    private var calendar: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        return calendar
    }

    @Test func createsAndPersistsTodoTemplateWithCurrentOccurrence() throws {
        let context = try makeContext()
        let todo = Todo(
            title: "Water plants",
            notes: "Blue watering can",
            scheduledDate: date(2026, 7, 1),
            order: "i",
            calendar: calendar
        )
        context.insert(todo)
        let rule = try RecurrenceRule.absolute(
            every: 2,
            unit: .week,
            anchors: [4, 0],
            reference: date(2026, 7, 1),
            calendar: calendar
        )

        let template = try RecurrencePersistence.createTemplate(
            for: todo,
            rule: rule,
            in: context
        )

        #expect(template.itemType == .todo)
        #expect(template.currentItemID == todo.id)
        #expect(template.currentSequence == 0)
        #expect(template.anchors == [0, 4])
        #expect(template.reference == date(2026, 6, 29))
        #expect(todo.recurrenceSequence == 0)
        #expect(todo.recurrenceTemplate?.id == template.id)
        #expect(template.todoOccurrences.map(\.id) == [todo.id])
        #expect(try template.rule(calendar: calendar) == rule)

        let verificationContext = ModelContext(context.container)
        let savedTemplates = try verificationContext.fetch(
            FetchDescriptor<RecurrenceTemplate>()
        )
        let savedTodos = try verificationContext.fetch(
            FetchDescriptor<Todo>()
        )
        #expect(savedTemplates.count == 1)
        #expect(savedTodos.count == 1)
        #expect(savedTodos.first?.recurrenceTemplate?.id == template.id)
    }

    @Test func completingRecurringTodoRetainsHistoryAndCreatesOneNextCurrent() throws {
        let context = try makeContext()
        let todo = insertTodo(
            "Original template title",
            notes: "Original template notes",
            day: date(2026, 7, 1),
            into: context
        )
        let rule = try RecurrenceRule.relative(every: 2, unit: .day)
        let template = try RecurrencePersistence.createTemplate(
            for: todo,
            rule: rule,
            in: context
        )

        todo.title = "Current occurrence only"
        todo.notes = "Current occurrence notes"
        template.title = "All future occurrences"
        template.notes = "Future notes"
        let completedAt = date(2026, 7, 1, hour: 17)

        let producedNext = try RecurrencePersistence.complete(
            todo,
            at: completedAt,
            in: context,
            calendar: calendar
        )
        let next = try #require(producedNext)

        #expect(todo.completedAt == completedAt)
        #expect(todo.title == "Current occurrence only")
        #expect(todo.notes == "Current occurrence notes")
        #expect(todo.recurrenceSequence == 0)
        #expect(next.completedAt == nil)
        #expect(next.scheduledDate == date(2026, 7, 3))
        #expect(next.title == "All future occurrences")
        #expect(next.notes == "Future notes")
        #expect(next.order == todo.order)
        #expect(next.recurrenceSequence == 1)
        #expect(next.recurrenceTemplate?.id == template.id)
        #expect(template.currentItemID == next.id)
        #expect(template.currentSequence == 1)
        #expect(Set(template.todoOccurrences.map(\.id)) == [todo.id, next.id])
        #expect(template.todoOccurrences.filter { $0.completedAt == nil }.count == 1)
    }

    @Test func completingTheSameOccurrenceTwiceDoesNotCreateDuplicate() throws {
        let context = try makeContext()
        let todo = insertTodo(
            "Repeat",
            day: date(2026, 7, 1),
            into: context
        )
        let rule = try RecurrenceRule.relative(every: 1, unit: .day)
        _ = try RecurrencePersistence.createTemplate(
            for: todo,
            rule: rule,
            in: context
        )
        _ = try RecurrencePersistence.complete(
            todo,
            in: context,
            calendar: calendar
        )

        let error = capturePersistenceError {
            _ = try RecurrencePersistence.complete(
                todo,
                in: context,
                calendar: calendar
            )
        }

        #expect(error?.code == "RECURRENCE-PERSIST-008")
        #expect(try context.fetch(FetchDescriptor<Todo>()).count == 2)
        #expect(
            try context.fetch(FetchDescriptor<Todo>())
                .filter { $0.completedAt == nil }
                .count == 1
        )
    }

    @Test func successiveCompletionsRetainEveryCompletedOccurrence() throws {
        let context = try makeContext()
        let first = insertTodo(
            "Repeat",
            day: date(2026, 7, 1),
            into: context
        )
        let rule = try RecurrenceRule.relative(every: 1, unit: .day)
        let template = try RecurrencePersistence.createTemplate(
            for: first,
            rule: rule,
            in: context
        )
        let producedSecond = try RecurrencePersistence.complete(
            first,
            in: context,
            calendar: calendar
        )
        let second = try #require(producedSecond)
        let producedThird = try RecurrencePersistence.complete(
            second,
            in: context,
            calendar: calendar
        )
        let third = try #require(producedThird)

        let todos = try context.fetch(FetchDescriptor<Todo>())
        #expect(todos.count == 3)
        #expect(todos.filter { $0.completedAt != nil }.count == 2)
        #expect(todos.filter { $0.completedAt == nil }.map(\.id) == [third.id])
        #expect(Set(todos.compactMap(\.recurrenceSequence)) == [0, 1, 2])
        #expect(template.currentItemID == third.id)
        #expect(template.currentSequence == 2)
    }

    @Test func completingNonRepeatingTodoDoesNotCreateAnotherTodo() throws {
        let context = try makeContext()
        let todo = insertTodo(
            "One time",
            day: date(2026, 7, 1),
            into: context
        )
        let completionDate = date(2026, 7, 1, hour: 18)

        let next = try RecurrencePersistence.complete(
            todo,
            at: completionDate,
            in: context,
            calendar: calendar
        )

        #expect(next == nil)
        #expect(todo.completedAt == completionDate)
        #expect(try context.fetch(FetchDescriptor<Todo>()).count == 1)
    }

    @Test func reinstatingTodoMovesItToEndOfToday() throws {
        let context = try makeContext()
        let today = date(2026, 7, 10)
        let existing = Todo(
            title: "Already Today",
            scheduledDate: today,
            order: "r",
            calendar: calendar
        )
        let completed = Todo(
            title: "Completed Early",
            notes: "Keep these notes",
            scheduledDate: date(2026, 7, 20),
            completedAt: date(2026, 7, 8, hour: 12),
            order: "9",
            calendar: calendar
        )
        context.insert(existing)
        context.insert(completed)
        try context.save()

        try RecurrencePersistence.reinstate(
            completed,
            on: today,
            in: context,
            calendar: calendar
        )

        #expect(completed.completedAt == nil)
        #expect(completed.scheduledDate == today)
        #expect(completed.notes == "Keep these notes")
        #expect(completed.order > existing.order)
        #expect(
            Item.ordered(todos: [completed, existing], events: [])
                .compactMap { item in
                    guard case .todo(let todo) = item else {
                        return nil
                    }
                    return todo.title
                } == ["Already Today", "Completed Early"]
        )
    }

    @Test func reinstatingRecurringHistoryDetachesOnlyThatOccurrence() throws {
        let context = try makeContext()
        let first = insertTodo(
            "Completed occurrence",
            notes: "Historical notes",
            day: date(2026, 7, 1),
            into: context
        )
        let rule = try RecurrenceRule.relative(every: 1, unit: .day)
        let template = try RecurrencePersistence.createTemplate(
            for: first,
            rule: rule,
            in: context
        )
        let producedCurrent = try RecurrencePersistence.complete(
            first,
            at: date(2026, 7, 1, hour: 17),
            in: context,
            calendar: calendar
        )
        let current = try #require(producedCurrent)

        try RecurrencePersistence.reinstate(
            first,
            on: date(2026, 7, 10),
            in: context,
            calendar: calendar
        )

        #expect(first.completedAt == nil)
        #expect(first.scheduledDate == date(2026, 7, 10))
        #expect(first.recurrenceTemplate == nil)
        #expect(first.recurrenceSequence == nil)
        #expect(first.notes == "Historical notes")
        #expect(current.recurrenceTemplate?.id == template.id)
        #expect(current.recurrenceSequence == 1)
        #expect(template.currentItemID == current.id)
        #expect(template.currentSequence == 1)
        #expect(template.todoOccurrences.map(\.id) == [current.id])
    }

    @Test func deletingRecurringHistoryPreservesCurrentOccurrence() throws {
        let context = try makeContext()
        let completed = insertTodo(
            "Completed occurrence",
            day: date(2026, 7, 1),
            into: context
        )
        let rule = try RecurrenceRule.relative(every: 1, unit: .day)
        let template = try RecurrencePersistence.createTemplate(
            for: completed,
            rule: rule,
            in: context
        )
        let producedCurrent = try RecurrencePersistence.complete(
            completed,
            at: date(2026, 7, 1, hour: 17),
            in: context,
            calendar: calendar
        )
        let current = try #require(producedCurrent)

        try RecurrencePersistence.deleteCompleted(
            completed,
            in: context
        )

        let todos = try context.fetch(FetchDescriptor<Todo>())
        #expect(todos.map(\.id) == [current.id])
        #expect(current.completedAt == nil)
        #expect(current.recurrenceTemplate?.id == template.id)
        #expect(template.currentItemID == current.id)
        #expect(template.currentSequence == 1)
        #expect(template.todoOccurrences.map(\.id) == [current.id])
    }

    @Test func cannotReinstateAnActiveTodo() throws {
        let context = try makeContext()
        let active = insertTodo(
            "Still active",
            day: date(2026, 7, 1),
            into: context
        )

        let error = capturePersistenceError {
            try RecurrencePersistence.reinstate(
                active,
                on: date(2026, 7, 10),
                in: context,
                calendar: calendar
            )
        }

        #expect(error?.code == "RECURRENCE-PERSIST-019")
        #expect(active.completedAt == nil)
        #expect(active.scheduledDate == date(2026, 7, 1))
    }

    @Test func deletingCurrentRecurringTodoSkipsItAndCreatesNext() throws {
        let context = try makeContext()
        let current = insertTodo(
            "Repeat",
            day: date(2026, 7, 1),
            into: context
        )
        let currentID = current.id
        let rule = try RecurrenceRule.relative(every: 1, unit: .week)
        let template = try RecurrencePersistence.createTemplate(
            for: current,
            rule: rule,
            in: context
        )

        let producedNext = try RecurrencePersistence.delete(
            current,
            in: context,
            calendar: calendar
        )
        let next = try #require(producedNext)

        let todos = try context.fetch(FetchDescriptor<Todo>())
        #expect(!todos.contains { $0.id == currentID })
        #expect(todos.map(\.id) == [next.id])
        #expect(next.completedAt == nil)
        #expect(next.scheduledDate == date(2026, 7, 8))
        #expect(next.recurrenceSequence == 1)
        #expect(template.currentItemID == next.id)
        #expect(template.todoOccurrences.map(\.id) == [next.id])
    }

    @Test func deletingTemplateKeepsCurrentAndCompletedTodos() throws {
        let context = try makeContext()
        let first = insertTodo(
            "Repeat",
            day: date(2026, 7, 1),
            into: context
        )
        let rule = try RecurrenceRule.relative(every: 1, unit: .day)
        let template = try RecurrencePersistence.createTemplate(
            for: first,
            rule: rule,
            in: context
        )
        let producedCurrent = try RecurrencePersistence.complete(
            first,
            in: context,
            calendar: calendar
        )
        let current = try #require(producedCurrent)

        try RecurrencePersistence.deleteTemplate(
            template,
            in: context
        )

        let todos = try context.fetch(FetchDescriptor<Todo>())
        #expect(todos.count == 2)
        #expect(todos.contains { $0.id == first.id && $0.completedAt != nil })
        #expect(todos.contains { $0.id == current.id && $0.completedAt == nil })
        #expect(todos.allSatisfy { $0.recurrenceTemplate == nil })
        #expect(todos.allSatisfy { $0.recurrenceSequence == nil })
        #expect(
            try context.fetch(FetchDescriptor<RecurrenceTemplate>()).isEmpty
        )
    }

    @Test func updatingTemplateChangesFutureRuleWithoutChangingCurrentTodo() throws {
        let context = try makeContext()
        let current = insertTodo(
            "Current title",
            notes: "Current notes",
            day: date(2026, 7, 1),
            into: context
        )
        let initialRule = try RecurrenceRule.relative(every: 1, unit: .day)
        let template = try RecurrencePersistence.createTemplate(
            for: current,
            rule: initialRule,
            in: context
        )
        let updatedRule = try RecurrenceRule.absolute(
            every: 2,
            unit: .week,
            anchors: [0, 3],
            reference: current.scheduledDate,
            calendar: calendar
        )

        try RecurrencePersistence.updateTemplate(
            template,
            rule: updatedRule,
            in: context
        )

        #expect(try template.rule(calendar: calendar) == updatedRule)
        #expect(current.title == "Current title")
        #expect(current.notes == "Current notes")
        #expect(current.scheduledDate == date(2026, 7, 1))
    }

    @Test func updatingEventTemplateChangesOnlyFutureWallTimes() throws {
        let context = try makeContext()
        let current = Event(
            title: "Current event",
            scheduledDate: date(2026, 7, 6, hour: 9),
            endDate: date(2026, 7, 6, hour: 10),
            order: "i"
        )
        context.insert(current)
        let rule = try RecurrenceRule.absolute(
            every: 1,
            unit: .week,
            anchors: [0],
            reference: current.scheduledDate,
            calendar: calendar
        )
        let template = try RecurrencePersistence.createTemplate(
            for: current,
            rule: rule,
            in: context,
            calendar: calendar
        )

        try RecurrencePersistence.updateTemplate(
            template,
            rule: rule,
            eventStartTimeSeconds: 13 * 3_600 + 30 * 60,
            eventEndTimeSeconds: 15 * 3_600,
            in: context
        )

        #expect(template.startTimeSeconds == 13 * 3_600 + 30 * 60)
        #expect(template.endTimeSeconds == 15 * 3_600)
        #expect(current.scheduledDate == date(2026, 7, 6, hour: 9))
        #expect(current.endDate == date(2026, 7, 6, hour: 10))
    }

    @Test func absoluteTodoCompletionUsesReferencePhaseAfterCurrentDateMoves() throws {
        let context = try makeContext()
        let current = insertTodo(
            "Alternating Monday",
            day: date(2026, 1, 5),
            into: context
        )
        let rule = try RecurrenceRule.absolute(
            every: 2,
            unit: .week,
            anchors: [0],
            reference: current.scheduledDate,
            calendar: calendar
        )
        _ = try RecurrencePersistence.createTemplate(
            for: current,
            rule: rule,
            in: context
        )
        current.scheduledDate = date(2026, 1, 13)

        let producedNext = try RecurrencePersistence.complete(
            current,
            in: context,
            calendar: calendar
        )
        let next = try #require(producedNext)

        #expect(next.scheduledDate == date(2026, 1, 19))
    }

    @Test func createsAbsoluteEventTemplateWithSameDayWallTimes() throws {
        let context = try makeContext()
        let event = Event(
            title: "Weekly call",
            notes: "Status update",
            scheduledDate: date(2026, 7, 1, hour: 9, minute: 30),
            endDate: date(2026, 7, 1, hour: 10, minute: 45),
            order: "i"
        )
        context.insert(event)
        let rule = try RecurrenceRule.absolute(
            every: 1,
            unit: .week,
            anchors: [2],
            reference: event.scheduledDate,
            calendar: calendar
        )

        let template = try RecurrencePersistence.createTemplate(
            for: event,
            rule: rule,
            in: context,
            calendar: calendar
        )

        #expect(template.itemType == .event)
        #expect(template.startTimeSeconds == 9 * 3_600 + 30 * 60)
        #expect(template.endTimeSeconds == 10 * 3_600 + 45 * 60)
        #expect(template.eventOccurrences.map(\.id) == [event.id])
        #expect(event.recurrenceTemplate?.id == template.id)
    }

    @Test func deletingRecurringEventCreatesNextWithSameWallTimes() throws {
        let context = try makeContext()
        let event = Event(
            title: "Weekly call",
            scheduledDate: date(2026, 7, 1, hour: 9, minute: 30),
            endDate: date(2026, 7, 1, hour: 10, minute: 45),
            order: "i"
        )
        context.insert(event)
        let eventID = event.id
        let rule = try RecurrenceRule.absolute(
            every: 1,
            unit: .week,
            anchors: [2],
            reference: event.scheduledDate,
            calendar: calendar
        )
        let template = try RecurrencePersistence.createTemplate(
            for: event,
            rule: rule,
            in: context,
            calendar: calendar
        )

        let producedNext = try RecurrencePersistence.delete(
            event,
            in: context,
            calendar: calendar
        )
        let next = try #require(producedNext)

        #expect(next.scheduledDate == date(2026, 7, 8, hour: 9, minute: 30))
        #expect(next.endDate == date(2026, 7, 8, hour: 10, minute: 45))
        #expect(next.recurrenceSequence == 1)
        #expect(template.currentItemID == next.id)
        #expect(template.eventOccurrences.map(\.id) == [next.id])
        let events = try context.fetch(FetchDescriptor<Event>())
        #expect(!events.contains { $0.id == eventID })
    }

    @Test func advancingPastRecurringEventCatchesUpInOneTransition() throws {
        let context = try makeContext()
        let event = Event(
            title: "Daily standup",
            scheduledDate: date(2026, 7, 1, hour: 9, minute: 30),
            endDate: date(2026, 7, 1, hour: 9, minute: 45),
            order: "i"
        )
        context.insert(event)
        let rule = try RecurrenceRule.absolute(
            every: 1,
            unit: .day,
            anchors: [],
            reference: event.scheduledDate,
            calendar: calendar
        )
        let template = try RecurrencePersistence.createTemplate(
            for: event,
            rule: rule,
            in: context,
            calendar: calendar
        )

        let current = try RecurrencePersistence.advance(
            event,
            through: date(2026, 7, 5),
            at: date(2026, 7, 5, hour: 8),
            in: context,
            calendar: calendar
        )

        #expect(current.scheduledDate == date(2026, 7, 5, hour: 9, minute: 30))
        #expect(current.endDate == date(2026, 7, 5, hour: 9, minute: 45))
        #expect(current.recurrenceSequence == 4)
        #expect(template.currentItemID == current.id)
        #expect(template.currentSequence == 4)
        #expect(template.eventOccurrences.map(\.id) == [current.id])
        #expect(try context.fetch(FetchDescriptor<Event>()).map(\.id) == [current.id])
    }

    @Test func advancingNonRepeatingEventFailsLoudly() throws {
        let context = try makeContext()
        let event = Event(
            title: "One time",
            scheduledDate: date(2026, 7, 1, hour: 9),
            order: "i"
        )
        context.insert(event)
        try context.save()

        let error = capturePersistenceError {
            _ = try RecurrencePersistence.advance(
                event,
                through: date(2026, 7, 5),
                in: context,
                calendar: calendar
            )
        }

        #expect(error?.code == "RECURRENCE-PERSIST-017")
        #expect(try context.fetch(FetchDescriptor<Event>()).map(\.id) == [event.id])
    }

    @Test func eventMaintenanceDeletesOneTimeEventsAndAdvancesRepeatingEvents() throws {
        let context = try makeContext()
        let oneTime = Event(
            title: "Old appointment",
            scheduledDate: date(2026, 7, 1, hour: 11),
            order: "a"
        )
        let repeating = Event(
            title: "Weekly call",
            scheduledDate: date(2026, 7, 1, hour: 9),
            endDate: date(2026, 7, 1, hour: 10),
            order: "i"
        )
        context.insert(oneTime)
        context.insert(repeating)
        let rule = try RecurrenceRule.absolute(
            every: 1,
            unit: .week,
            anchors: [2],
            reference: repeating.scheduledDate,
            calendar: calendar
        )
        let template = try RecurrencePersistence.createTemplate(
            for: repeating,
            rule: rule,
            in: context,
            calendar: calendar
        )

        try EventMaintenance.deletePastEvents(
            in: context,
            calendar: calendar,
            now: date(2026, 7, 23, hour: 8)
        )

        let events = try context.fetch(FetchDescriptor<Event>())
        let current = try #require(events.first)
        #expect(events.count == 1)
        #expect(current.title == "Weekly call")
        #expect(current.scheduledDate == date(2026, 7, 29, hour: 9))
        #expect(current.endDate == date(2026, 7, 29, hour: 10))
        #expect(current.recurrenceSequence == 4)
        #expect(template.currentItemID == current.id)
    }

    @Test func eventMaintenanceRollsBackTheWholeBatchWhenRecurrenceIsCorrupt() throws {
        let context = try makeContext()
        let oneTime = Event(
            title: "Old appointment",
            scheduledDate: date(2026, 7, 1, hour: 11),
            order: "a"
        )
        let repeating = Event(
            title: "Weekly call",
            scheduledDate: date(2026, 7, 1, hour: 9),
            order: "i"
        )
        context.insert(oneTime)
        context.insert(repeating)
        let rule = try RecurrenceRule.absolute(
            every: 1,
            unit: .week,
            anchors: [2],
            reference: repeating.scheduledDate,
            calendar: calendar
        )
        let template = try RecurrencePersistence.createTemplate(
            for: repeating,
            rule: rule,
            in: context,
            calendar: calendar
        )
        let unexpectedCurrent = Event(
            title: "Corrupt second current",
            scheduledDate: date(2026, 7, 8, hour: 9),
            order: "z"
        )
        context.insert(unexpectedCurrent)
        unexpectedCurrent.recurrenceSequence = template.currentSequence
        unexpectedCurrent.recurrenceTemplate = template
        try context.save()

        let error = capturePersistenceError {
            try EventMaintenance.deletePastEvents(
                in: context,
                calendar: calendar,
                now: date(2026, 7, 23, hour: 8)
            )
        }

        #expect(error != nil)
        let events = try context.fetch(FetchDescriptor<Event>())
        #expect(Set(events.map(\.id)) == [
            oneTime.id,
            repeating.id,
            unexpectedCurrent.id
        ])
        #expect(template.currentItemID == repeating.id)
        #expect(template.currentSequence == 0)
    }

    @Test func rejectsRelativeEventRecurrence() throws {
        let context = try makeContext()
        let event = Event(
            title: "Event",
            scheduledDate: date(2026, 7, 1, hour: 9),
            order: "i"
        )
        context.insert(event)
        let rule = try RecurrenceRule.relative(every: 1, unit: .week)

        let error = capturePersistenceError {
            _ = try RecurrencePersistence.createTemplate(
                for: event,
                rule: rule,
                in: context,
                calendar: calendar
            )
        }

        #expect(error?.code == "RECURRENCE-PERSIST-002")
        #expect(event.recurrenceTemplate == nil)
        #expect(
            try context.fetch(FetchDescriptor<RecurrenceTemplate>()).isEmpty
        )
    }

    @Test func rejectsEventThatCrossesDateBoundary() throws {
        let context = try makeContext()
        let event = Event(
            title: "Overnight",
            scheduledDate: date(2026, 7, 1, hour: 23),
            endDate: date(2026, 7, 2, hour: 1),
            order: "i"
        )
        context.insert(event)
        let rule = try RecurrenceRule.absolute(
            every: 1,
            unit: .week,
            anchors: [2],
            reference: event.scheduledDate,
            calendar: calendar
        )

        let error = capturePersistenceError {
            _ = try RecurrencePersistence.createTemplate(
                for: event,
                rule: rule,
                in: context,
                calendar: calendar
            )
        }

        #expect(error?.code == "RECURRENCE-PERSIST-003")
        #expect(event.recurrenceTemplate == nil)
    }

    @Test func rejectsEventThatEndsBeforeItStarts() throws {
        let context = try makeContext()
        let event = Event(
            title: "Backwards",
            scheduledDate: date(2026, 7, 1, hour: 10),
            endDate: date(2026, 7, 1, hour: 9),
            order: "i"
        )
        context.insert(event)
        let rule = try RecurrenceRule.absolute(
            every: 1,
            unit: .week,
            anchors: [2],
            reference: event.scheduledDate,
            calendar: calendar
        )

        let error = capturePersistenceError {
            _ = try RecurrencePersistence.createTemplate(
                for: event,
                rule: rule,
                in: context,
                calendar: calendar
            )
        }

        #expect(error?.code == "RECURRENCE-PERSIST-004")
        #expect(event.recurrenceTemplate == nil)
    }

    @Test func corruptMultipleCurrentTodosFailLoudlyWithoutGeneratingAnother() throws {
        let context = try makeContext()
        let current = insertTodo(
            "Current",
            day: date(2026, 7, 1),
            into: context
        )
        let rule = try RecurrenceRule.relative(every: 1, unit: .day)
        let template = try RecurrencePersistence.createTemplate(
            for: current,
            rule: rule,
            in: context
        )
        let unexpected = insertTodo(
            "Unexpected second current",
            day: date(2026, 7, 2),
            into: context
        )
        unexpected.recurrenceSequence = 0
        unexpected.recurrenceTemplate = template
        try context.save()

        let error = capturePersistenceError {
            _ = try RecurrencePersistence.complete(
                current,
                in: context,
                calendar: calendar
            )
        }

        #expect(error?.code == "RECURRENCE-PERSIST-009")
        #expect(try context.fetch(FetchDescriptor<Todo>()).count == 2)
        #expect(current.completedAt == nil)
    }

    @Test func cannotAttachSecondTemplateToSameItem() throws {
        let context = try makeContext()
        let todo = insertTodo(
            "Repeat",
            day: date(2026, 7, 1),
            into: context
        )
        let rule = try RecurrenceRule.relative(every: 1, unit: .day)
        _ = try RecurrencePersistence.createTemplate(
            for: todo,
            rule: rule,
            in: context
        )

        let error = capturePersistenceError {
            _ = try RecurrencePersistence.createTemplate(
                for: todo,
                rule: rule,
                in: context
            )
        }

        #expect(error?.code == "RECURRENCE-PERSIST-001")
        #expect(
            try context.fetch(FetchDescriptor<RecurrenceTemplate>()).count == 1
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
        notes: String? = nil,
        day: Date,
        into context: ModelContext
    ) -> Todo {
        let todo = Todo(
            title: title,
            notes: notes,
            scheduledDate: day,
            order: "i",
            calendar: calendar
        )
        context.insert(todo)
        return todo
    }

    private func date(
        _ year: Int,
        _ month: Int,
        _ day: Int,
        hour: Int = 0,
        minute: Int = 0
    ) -> Date {
        calendar.date(
            from: DateComponents(
                year: year,
                month: month,
                day: day,
                hour: hour,
                minute: minute
            )
        )!
    }

    private func capturePersistenceError(
        _ operation: () throws -> Void
    ) -> RecurrencePersistenceError? {
        do {
            try operation()
            Issue.record("Expected recurrence persistence to throw")
            return nil
        } catch let error as RecurrencePersistenceError {
            return error
        } catch {
            Issue.record("Unexpected error type: \(error)")
            return nil
        }
    }
}
