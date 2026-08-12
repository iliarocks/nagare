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
        let result = try NagareIntentSemantics.todoDate(
            from: nil,
            now: date(2026, 8, 3, hour: 18),
            calendar: calendar
        )

        #expect(result == date(2026, 8, 3))
    }

    @Test func todoAcceptsTomorrowWithoutAddingATime() throws {
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

    @Test func todoRejectsExplicitTimesAndPastDates() {
        let timed = DateComponents(
            calendar: calendar,
            timeZone: calendar.timeZone,
            year: 2026,
            month: 8,
            day: 4,
            hour: 15
        )
        #expect(throws: NagareIntentError.todoCannotHaveTime) {
            try NagareIntentSemantics.todoDate(
                from: timed,
                now: date(2026, 8, 3),
                calendar: calendar
            )
        }

        let past = DateComponents(
            calendar: calendar,
            timeZone: calendar.timeZone,
            year: 2026,
            month: 8,
            day: 2
        )
        #expect(throws: NagareIntentError.pastTodoDate) {
            try NagareIntentSemantics.todoDate(
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
        #expect(snapshot.endDate == nil)
        let persisted = try fixture.repository.load()
        #expect(persisted.todos.count == 1)
        #expect(persisted.recurrenceTemplates.isEmpty)
    }

    @Test func storeCreatesEventsWithOrWithoutAnEnd() throws {
        let fixture = try makeFixture()
        let store = fixture.store
        let basketball = date(2026, 8, 8, hour: 18, minute: 30)
        let hangStart = date(2026, 8, 8, hour: 16)
        let hangEnd = date(2026, 8, 8, hour: 17)

        let openEnded = try store.createEvent(
            title: "Play Basketball",
            notes: nil,
            scheduledDate: basketball,
            endDate: nil
        )
        let ranged = try store.createEvent(
            title: "Bro's Hang",
            notes: nil,
            scheduledDate: hangStart,
            endDate: hangEnd
        )

        #expect(openEnded.scheduledDate == basketball)
        #expect(openEnded.endDate == nil)
        #expect(ranged.scheduledDate == hangStart)
        #expect(ranged.endDate == hangEnd)
        let persisted = try fixture.repository.load()
        #expect(persisted.events.count == 2)
        #expect(persisted.recurrenceTemplates.isEmpty)
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
