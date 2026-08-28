import Foundation
import SwiftData
import Testing
@testable import Nagare

@MainActor
struct NagareIntentSemanticsTests {
    private struct Fixture {
        let store: NagareIntentStore
        let repository: SwiftDataNagareRepository
    }

    private var calendar: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        return calendar
    }

    @Test func titleIsTrimmedAndMustNotBeEmpty() throws {
        #expect(
            try NagareIntentSemantics.title(from: "  Buy cereal  ")
                == "Buy cereal"
        )
        #expect(throws: NagareIntentError.emptyTitle) {
            try NagareIntentSemantics.title(from: "  \n ")
        }
    }

    @Test func todoWithoutDateDefaultsToToday() throws {
        let result = try NagareIntentSemantics.todoSchedule(
            from: nil,
            now: date(2026, 8, 3, hour: 18),
            calendar: calendar
        )

        #expect(result.scheduledDate == date(2026, 8, 3))
        #expect(!result.includesTime)
    }

    @Test func todoAcceptsTomorrowWithoutAddingATime() throws {
        let components = DateComponents(
            calendar: calendar,
            timeZone: calendar.timeZone,
            year: 2026,
            month: 8,
            day: 4
        )

        let result = try NagareIntentSemantics.todoSchedule(
            from: components,
            now: date(2026, 8, 3, hour: 18),
            calendar: calendar
        )

        #expect(result.scheduledDate == date(2026, 8, 4))
        #expect(!result.includesTime)
    }

    @Test func todoAcceptsExplicitTimesButStillRejectsPastDays() throws {
        let timed = DateComponents(
            calendar: calendar,
            timeZone: calendar.timeZone,
            year: 2026,
            month: 8,
            day: 4,
            hour: 15
        )
        let result = try NagareIntentSemantics.todoSchedule(
            from: timed,
            now: date(2026, 8, 3),
            calendar: calendar
        )
        #expect(result.scheduledDate == date(2026, 8, 4, hour: 15))
        #expect(result.includesTime)

        let past = DateComponents(
            calendar: calendar,
            timeZone: calendar.timeZone,
            year: 2026,
            month: 8,
            day: 2
        )
        #expect(throws: NagareIntentError.pastTodoDate) {
            try NagareIntentSemantics.todoSchedule(
                from: past,
                now: date(2026, 8, 3),
                calendar: calendar
            )
        }
    }

    @Test func eventAllowsAnOptionalEndButRejectsInvalidRanges() throws {
        let start = date(2026, 8, 8, hour: 16)
        let end = date(2026, 8, 8, hour: 17)

        try NagareIntentSemantics.validateEventRange(
            startDate: start,
            endDate: nil
        )
        try NagareIntentSemantics.validateEventRange(
            startDate: start,
            endDate: end
        )
        #expect(throws: NagareIntentError.eventEndBeforeStart) {
            try NagareIntentSemantics.validateEventRange(
                startDate: start,
                endDate: start
            )
        }
    }

    @Test func storeCreatesOnlyAStandardTodo() throws {
        let fixture = try makeFixture()
        let store = fixture.store
        let tomorrow = date(2026, 8, 4)

        let snapshot = try store.createTodo(
            title: "Buy cereal",
            notes: nil,
            scheduledDate: tomorrow,
            calendar: calendar
        )

        #expect(snapshot.title == "Buy cereal")
        #expect(snapshot.scheduledDate == tomorrow)
        #expect(!snapshot.includesTime)
        #expect(snapshot.endDate == nil)
        let persisted = try fixture.repository.load()
        #expect(persisted.todos.count == 1)
        #expect(persisted.todos.first?.includesTime == false)
        #expect(persisted.recurrenceTemplates.isEmpty)
    }

    @Test func storeCreatesTimedTodosWithOrWithoutAnEnd() throws {
        let fixture = try makeFixture()
        let store = fixture.store
        let basketball = date(2026, 8, 8, hour: 18, minute: 30)
        let hangStart = date(2026, 8, 8, hour: 16)
        let hangEnd = date(2026, 8, 8, hour: 17)

        let openEnded = try store.createTimedTodo(
            title: "Play Basketball",
            notes: nil,
            scheduledDate: basketball,
            endDate: nil
        )
        let ranged = try store.createTimedTodo(
            title: "Bro's Hang",
            notes: nil,
            scheduledDate: hangStart,
            endDate: hangEnd
        )

        #expect(openEnded.scheduledDate == basketball)
        #expect(openEnded.includesTime)
        #expect(openEnded.endDate == nil)
        #expect(ranged.scheduledDate == hangStart)
        #expect(ranged.includesTime)
        #expect(ranged.endDate == hangEnd)
        let persisted = try fixture.repository.load()
        #expect(persisted.todos.count == 2)
        #expect(persisted.todos.allSatisfy { $0.includesTime })
        #expect(persisted.recurrenceTemplates.isEmpty)
    }

    @Test func reminderStoreCreatesATimedTodo() throws {
        let fixture = try makeFixture()
        let scheduledDate = date(2026, 8, 8, hour: 18, minute: 30)

        let snapshot = try fixture.store.createTodo(
            title: "Play Basketball",
            notes: nil,
            scheduledDate: scheduledDate,
            includesTime: true,
            calendar: calendar
        )

        #expect(snapshot.scheduledDate == scheduledDate)
        #expect(snapshot.includesTime)
        let persisted = try fixture.repository.load()
        #expect(persisted.todos.first?.scheduledDate == scheduledDate)
        #expect(persisted.todos.first?.includesTime == true)
    }

    private func makeFixture() throws -> Fixture {
        let container = try ModelContainer(
            for: Project.self,
            Todo.self,
            Event.self,
            RecurrenceTemplate.self,
            configurations: ModelConfiguration(
                isStoredInMemoryOnly: true,
                cloudKitDatabase: .none
            )
        )
        let repository = SwiftDataNagareRepository(modelContainer: container)
        return Fixture(
            store: NagareIntentStore(
                orchestrator: NagareDataOrchestrator(
                    reader: repository,
                    writer: repository
                )
            ),
            repository: repository
        )
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
}
