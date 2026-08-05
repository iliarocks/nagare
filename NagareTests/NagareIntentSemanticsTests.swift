import Foundation
import SwiftData
import Testing
@testable import Nagare

@MainActor
struct NagareIntentSemanticsTests {
    private var calendar: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        return calendar
    }

    @Test func todoRejectsAnyExplicitTimeComponent() {
        let components = DateComponents(
            calendar: calendar,
            timeZone: calendar.timeZone,
            year: 2026,
            month: 8,
            day: 4,
            hour: 15
        )

        #expect(throws: NagareIntentError.todoCannotHaveTime) {
            try NagareIntentSemantics.todoDate(
                from: components,
                now: date(2026, 8, 3),
                calendar: calendar
            )
        }
    }

    @Test func todoAcceptsDateOnlyComponents() throws {
        let components = DateComponents(
            calendar: calendar,
            timeZone: calendar.timeZone,
            year: 2026,
            month: 8,
            day: 4
        )

        let result = try NagareIntentSemantics.todoDate(
            from: components,
            now: date(2026, 8, 3, hour: 18),
            calendar: calendar
        )

        #expect(result == date(2026, 8, 4))
    }

    @Test func todoWithoutDateDefaultsToToday() throws {
        let result = try NagareIntentSemantics.todoDate(
            from: nil,
            now: date(2026, 8, 3, hour: 18),
            calendar: calendar
        )

        #expect(result == date(2026, 8, 3))
    }

    @Test func todoRejectsPastDate() {
        let components = DateComponents(
            calendar: calendar,
            timeZone: calendar.timeZone,
            year: 2026,
            month: 8,
            day: 2
        )

        #expect(throws: NagareIntentError.pastTodoDate) {
            try NagareIntentSemantics.todoDate(
                from: components,
                now: date(2026, 8, 3),
                calendar: calendar
            )
        }
    }

    @Test func relativeNagareRecurrenceIsNotMisrepresentedToSiri() throws {
        let relative = try RecurrenceRule.relative(every: 1, unit: .week)
        #expect(
            NagareRecurrenceBridge.systemRule(
                from: relative,
                calendar: calendar
            ) == nil
        )
    }

    @Test func intentStoreCreatesItemsUsingTheSameTodayOrder() throws {
        let store = try makeStore()
        let today = calendar.startOfDay(for: .now)
        let eventTime = calendar.date(
            bySettingHour: 15,
            minute: 0,
            second: 0,
            of: today
        )!

        let todo = try store.createTodo(
            title: "Call Alex",
            notes: nil,
            scheduledDate: today,
            recurrence: nil
        )
        let event = try store.createEvent(
            title: "Coffee",
            notes: nil,
            scheduledDate: eventTime,
            endDate: nil,
            recurrence: nil
        )

        #expect(todo.order < event.order)
        let snapshots = try store.todayItemSnapshots(
            on: today,
            calendar: calendar
        )
        let expectedItems = Item.ordered(todos: [todo], events: [event])
        let expectedTitles = expectedItems.map { item in
            switch item {
            case .todo(let todo): todo.title
            case .event(let event): event.title
            }
        }
        let expectedKinds = expectedItems.map { item in
            switch item {
            case .todo: NagareIntentItemKind.todo
            case .event: NagareIntentItemKind.event
            }
        }

        #expect(snapshots.map(\.title) == expectedTitles)
        #expect(snapshots.map(\.kind) == expectedKinds)
    }

    @Test func itemAfterTitleNeverEscapesToday() throws {
        let store = try makeStore()
        let localCalendar = Calendar.autoupdatingCurrent
        let today = localCalendar.startOfDay(for: .now)
        let tomorrow = try #require(
            localCalendar.date(byAdding: .day, value: 1, to: today)
        )

        _ = try store.createTodo(
            title: "First",
            notes: nil,
            scheduledDate: today,
            recurrence: nil
        )
        _ = try store.createTodo(
            title: "Second",
            notes: nil,
            scheduledDate: today,
            recurrence: nil
        )
        _ = try store.createTodo(
            title: "Future",
            notes: nil,
            scheduledDate: tomorrow,
            recurrence: nil
        )

        let next = try store.todayItemSnapshot(
            afterTitle: "First",
            on: today,
            calendar: localCalendar
        )
        #expect(next?.title == "Second")

        #expect(throws: NagareIntentError.itemNotOnToday) {
            try store.todayItemSnapshot(
                afterTitle: "Future",
                on: today,
                calendar: localCalendar
            )
        }
    }

    @Test func completingRelativeTodoSchedulesFromCompletion() throws {
        let store = try makeStore()
        let localCalendar = Calendar.autoupdatingCurrent
        let today = localCalendar.startOfDay(for: .now)
        let completion = try #require(
            localCalendar.date(byAdding: .hour, value: 15, to: today)
        )
        let rule = try RecurrenceRule.relative(every: 5, unit: .day)
        let todo = try store.createTodo(
            title: "Wash dishes",
            notes: nil,
            scheduledDate: today,
            recurrence: rule
        )

        let result = try store.setTodoCompletion(
            todo.id,
            isCompleted: true,
            at: completion,
            calendar: localCalendar
        )
        let expectedNextDate = try #require(
            localCalendar.date(byAdding: .day, value: 5, to: today)
        )

        #expect(result.item.completedAt == completion)
        #expect(result.nextOccurrence?.scheduledDate == expectedNextDate)
        #expect(result.nextOccurrence?.recurrence?.mode == .relative)
    }

    @Test func deletingRepeatingTodoSkipsOnlyCurrentOccurrence() throws {
        let store = try makeStore()
        let localCalendar = Calendar.autoupdatingCurrent
        let today = localCalendar.startOfDay(for: .now)
        let rule = try RecurrenceRule.relative(every: 2, unit: .day)
        let todo = try store.createTodo(
            title: "Water plants",
            notes: nil,
            scheduledDate: today,
            recurrence: rule
        )

        let results = try store.deleteTodos(
            identifiedBy: [todo.id],
            at: today,
            calendar: localCalendar
        )
        let expectedNextDate = try #require(
            localCalendar.date(byAdding: .day, value: 2, to: today)
        )

        #expect(results.count == 1)
        #expect(results.first?.nextOccurrence?.scheduledDate == expectedNextDate)
        #expect(try store.todoSnapshots().map(\.title) == ["Water plants"])
    }

    @Test func deletingOrdinaryEventRemovesIt() throws {
        let store = try makeStore()
        let localCalendar = Calendar.autoupdatingCurrent
        let today = localCalendar.startOfDay(for: .now)
        let eventTime = try #require(
            localCalendar.date(
                bySettingHour: 10,
                minute: 0,
                second: 0,
                of: today
            )
        )
        let event = try store.createEvent(
            title: "Dentist",
            notes: nil,
            scheduledDate: eventTime,
            endDate: nil,
            recurrence: nil
        )

        let result = try store.deleteEvent(
            identifiedBy: event.id,
            span: nil,
            at: eventTime,
            calendar: localCalendar
        )

        #expect(result.nextOccurrence == nil)
        #expect(try store.eventSnapshots().isEmpty)
    }

    @Test func deletingThisRepeatingEventAdvancesTheSeries() throws {
        let store = try makeStore()
        let localCalendar = Calendar.autoupdatingCurrent
        let today = localCalendar.startOfDay(for: .now)
        let eventTime = try #require(
            localCalendar.date(
                bySettingHour: 10,
                minute: 0,
                second: 0,
                of: today
            )
        )
        let rule = try RecurrenceRule.absolute(
            every: 1,
            unit: .day,
            reference: eventTime,
            calendar: localCalendar
        )
        let event = try store.createEvent(
            title: "Standup",
            notes: nil,
            scheduledDate: eventTime,
            endDate: nil,
            recurrence: rule
        )

        let result = try store.deleteEvent(
            identifiedBy: event.id,
            span: .this,
            at: eventTime,
            calendar: localCalendar
        )
        let expectedNextDate = try #require(
            localCalendar.date(byAdding: .day, value: 1, to: eventTime)
        )
        let remainingEvents = try store.eventSnapshots()

        #expect(result.nextOccurrence?.scheduledDate == expectedNextDate)
        #expect(remainingEvents.count == 1)
        #expect(remainingEvents.first?.id != event.id)
    }

    @Test func deletingFutureOrAllRepeatingEventsRemovesTheSeries() throws {
        for span in [NagareEventSpan.future, .all] {
            let store = try makeStore()
            let localCalendar = Calendar.autoupdatingCurrent
            let today = localCalendar.startOfDay(for: .now)
            let eventTime = try #require(
                localCalendar.date(
                    bySettingHour: 10,
                    minute: 0,
                    second: 0,
                    of: today
                )
            )
            let rule = try RecurrenceRule.absolute(
                every: 1,
                unit: .day,
                reference: eventTime,
                calendar: localCalendar
            )
            let event = try store.createEvent(
                title: "Standup",
                notes: nil,
                scheduledDate: eventTime,
                endDate: nil,
                recurrence: rule
            )

            let result = try store.deleteEvent(
                identifiedBy: event.id,
                span: span,
                at: eventTime,
                calendar: localCalendar
            )
            let templates = try store.modelContext.fetch(
                FetchDescriptor<RecurrenceTemplate>()
            )

            #expect(result.nextOccurrence == nil)
            #expect(try store.eventSnapshots().isEmpty)
            #expect(templates.isEmpty)
        }
    }

    private func makeStore() throws -> NagareIntentStore {
        let container = try ModelContainer(
            for: Project.self,
            Todo.self,
            Event.self,
            RecurrenceTemplate.self,
            configurations: ModelConfiguration(isStoredInMemoryOnly: true)
        )
        return NagareIntentStore(modelContainer: container)
    }

    private func date(
        _ year: Int,
        _ month: Int,
        _ day: Int,
        hour: Int = 0
    ) -> Date {
        calendar.date(
            from: DateComponents(
                year: year,
                month: month,
                day: day,
                hour: hour
            )
        )!
    }
}
