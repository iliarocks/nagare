import Foundation
import Testing
@testable import Nagare

struct CalendarDayTests {
    @Test func midnightMovesTheSharedBoundaryToTheFollowingDay() throws {
        let calendar = try calendar(in: "America/Los_Angeles")
        let before = NagareCalendarDay(
            now: try date("2026-10-02T06:59:59Z"),
            calendar: calendar
        )
        let after = NagareCalendarDay(
            now: try date("2026-10-02T07:00:00Z"),
            calendar: calendar
        )

        #expect(before.nextStart == after.start)
        #expect(before != after)
        #expect(after.start == (try date("2026-10-02T07:00:00Z")))
        #expect(after.nextStart == (try date("2026-10-03T07:00:00Z")))
    }

    @Test(arguments: [
        ("2026-03-08T08:00:00Z", "2026-03-09T07:00:00Z", 23.0),
        ("2026-11-01T07:00:00Z", "2026-11-02T08:00:00Z", 25.0)
    ])
    func nextMidnightUsesTheCalendarAcrossDaylightSavingChanges(
        start: String,
        nextStart: String,
        hours: Double
    ) throws {
        let day = NagareCalendarDay(
            now: try date(start),
            calendar: try calendar(in: "America/Los_Angeles")
        )
        let boundary = try #require(day.nextStart)

        #expect(boundary == (try date(nextStart)))
        #expect(boundary.timeIntervalSince(day.start) == hours * 3_600)
    }

    @Test func timeZoneChangeRefreshesBoundariesEvenOnTheSameLocalDate() throws {
        let now = try date("2026-10-01T20:00:00Z")
        let losAngeles = NagareCalendarDay(
            now: now,
            calendar: try calendar(in: "America/Los_Angeles")
        )
        let newYork = NagareCalendarDay(
            now: now,
            calendar: try calendar(in: "America/New_York")
        )

        #expect(losAngeles != newYork)
        #expect(losAngeles.nextStart == (try date("2026-10-02T07:00:00Z")))
        #expect(newYork.nextStart == (try date("2026-10-02T04:00:00Z")))
    }

    @Test func clockChangesWithinTheSameDayKeepOneDayValue() throws {
        let calendar = try calendar(in: "America/Los_Angeles")
        let morning = NagareCalendarDay(
            now: try date("2026-10-01T16:00:00Z"),
            calendar: calendar
        )
        let afternoon = NagareCalendarDay(
            now: try date("2026-10-01T23:00:00Z"),
            calendar: calendar
        )

        #expect(morning == afternoon)
    }

    private func calendar(in timeZoneID: String) throws -> Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = try #require(TimeZone(identifier: timeZoneID))
        return calendar
    }

    private func date(_ value: String) throws -> Date {
        try #require(ISO8601DateFormatter().date(from: value))
    }
}
