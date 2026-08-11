import Foundation
import SwiftData
import Testing
@testable import Nagare

struct ICalendarTests {
    private let pacific = TimeZone(identifier: "America/Los_Angeles")!

    @Test func parsesGoogleInviteWithTimeZoneFoldingAndMetadata() throws {
        let invite = """
        BEGIN:VCALENDAR\r
        VERSION:2.0\r
        BEGIN:VTIMEZONE\r
        TZID:America/Los_Angeles\r
        END:VTIMEZONE\r
        BEGIN:VEVENT\r
        UID:friends-night@example.com\r
        DTSTART;TZID=America/Los_Angeles:20260815T160000\r
        DTEND;TZID=America/Los_Angeles:20260815T170000\r
        SUMMARY:Bro's Hang at the\r
         park\r
        DESCRIPTION:Bring snacks\\, water\\; and a ball\\nSee you there.\r
        LOCATION:Golden Gate Park\r
        BEGIN:VALARM\r
        DESCRIPTION:This nested description must be ignored\r
        END:VALARM\r
        END:VEVENT\r
        END:VCALENDAR\r
        """

        let draft = try ICalendarParser.parse(
            invite,
            defaultTimeZone: pacific
        )

        #expect(draft.sourceIdentifier == "friends-night@example.com")
        #expect(draft.title == "Bro's Hang at thepark")
        #expect(
            draft.notes
                == "Bring snacks, water; and a ball\nSee you there.\n\nLocation: Golden Gate Park"
        )
        #expect(
            calendar(pacific).dateComponents(
                [.year, .month, .day, .hour, .minute],
                from: draft.scheduledDate
            ) == DateComponents(
                year: 2026,
                month: 8,
                day: 15,
                hour: 16,
                minute: 0
            )
        )
        #expect(draft.endDate?.timeIntervalSince(draft.scheduledDate) == 3_600)
        #expect(!draft.isAllDay)
    }

    @Test func parsesUTCAndAllDayEvents() throws {
        let timed = try ICalendarParser.parse(
            """
            BEGIN:VCALENDAR
            BEGIN:VEVENT
            UID:basketball@example.com
            DTSTART:20260816T013000Z
            SUMMARY:Play Basketball
            END:VEVENT
            END:VCALENDAR
            """,
            defaultTimeZone: pacific
        )
        let utcCalendar = calendar(TimeZone(secondsFromGMT: 0)!)
        #expect(
            utcCalendar.dateComponents(
                [.year, .month, .day, .hour, .minute],
                from: timed.scheduledDate
            ) == DateComponents(
                year: 2026,
                month: 8,
                day: 16,
                hour: 1,
                minute: 30
            )
        )

        let allDay = try ICalendarParser.parse(
            """
            BEGIN:VCALENDAR
            BEGIN:VEVENT
            UID:day@example.com
            DTSTART;VALUE=DATE:20260822
            DTEND;VALUE=DATE:20260823
            SUMMARY:All Day
            END:VEVENT
            END:VCALENDAR
            """,
            defaultTimeZone: pacific
        )
        #expect(allDay.isAllDay)
        #expect(allDay.endDate == nil)
        #expect(calendar(pacific).component(.day, from: allDay.scheduledDate) == 22)
        #expect(calendar(pacific).component(.hour, from: allDay.scheduledDate) == 0)
    }

    @Test func rejectsCancelledAndBackwardsEvents() {
        #expect(throws: ICalendarError.cancelledEvent) {
            try ICalendarParser.parse(
                """
                BEGIN:VEVENT
                STATUS:CANCELLED
                DTSTART:20260815T160000Z
                END:VEVENT
                """,
                defaultTimeZone: pacific
            )
        }

        #expect(throws: ICalendarError.invalidEndDate) {
            try ICalendarParser.parse(
                """
                BEGIN:VEVENT
                DTSTART:20260815T170000Z
                DTEND:20260815T160000Z
                END:VEVENT
                """,
                defaultTimeZone: pacific
            )
        }
    }

    @Test func exportedInviteRoundTripsAndUsesCompliantLineFolding() throws {
        let start = try #require(calendar(pacific).date(
            from: DateComponents(
                year: 2026,
                month: 8,
                day: 15,
                hour: 16
            )
        ))
        let original = ICalendarEventDraft(
            sourceIdentifier: "nagare-event@example.com",
            title: String(repeating: "Friends 🎉 ", count: 10),
            notes: "Bring snacks, water; and a ball\nSecond line",
            scheduledDate: start,
            endDate: start.addingTimeInterval(3_600),
            isAllDay: false
        )
        let data = ICalendarSerializer.serialize(
            original,
            generatedAt: Date(timeIntervalSince1970: 0)
        )
        let text = try #require(String(data: data, encoding: .utf8))

        #expect(text.contains("BEGIN:VCALENDAR\r\n"))
        #expect(text.contains("DTSTART:20260815T230000Z"))
        #expect(
            text.components(separatedBy: "\r\n")
                .filter { !$0.isEmpty }
                .allSatisfy { $0.utf8.count <= 75 }
        )

        let roundTrip = try ICalendarParser.parse(
            data,
            defaultTimeZone: pacific
        )
        #expect(roundTrip == original)
    }

    @Test @MainActor
    func exportStoreWritesARealNamedCalendarFile() throws {
        let directory = FileManager.default.temporaryDirectory.appending(
            path: UUID().uuidString,
            directoryHint: .isDirectory
        )
        defer { try? FileManager.default.removeItem(at: directory) }
        let event = Event(
            title: "Birthday/Dinner",
            notes: "Bring cake",
            scheduledDate: Date(timeIntervalSince1970: 100),
            endDate: Date(timeIntervalSince1970: 200),
            order: "i"
        )

        let sharedFile = try ICalendarExportStore.write(
            ICalendarExportFile(
                event: event,
                generatedAt: Date(timeIntervalSince1970: 0)
            ),
            to: directory,
            id: UUID(uuidString: "00000000-0000-0000-0000-000000000001")!
        )

        #expect(sharedFile.fileURL.lastPathComponent == "Birthday-Dinner.ics")
        #expect(sharedFile.fileURL.pathExtension == "ics")
        #expect(FileManager.default.fileExists(atPath: sharedFile.fileURL.path))
        #expect(sharedFile.subject == "Birthday/Dinner")
        _ = try ICalendarParser.parse(
            Data(contentsOf: sharedFile.fileURL),
            defaultTimeZone: pacific
        )
    }

    private func calendar(_ timeZone: TimeZone) -> Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = timeZone
        return calendar
    }
}

@MainActor
struct CalendarImportPersistenceTests {
    @Test func repeatedUIDUpdatesExistingEventInsteadOfDuplicating() throws {
        let context = try makeContext()
        let sourceIdentifier = "same-invite@example.com"
        let first = ICalendarEventDraft(
            sourceIdentifier: sourceIdentifier,
            title: "Original",
            notes: nil,
            scheduledDate: Date(timeIntervalSince1970: 100),
            endDate: Date(timeIntervalSince1970: 200),
            isAllDay: false
        )
        let second = ICalendarEventDraft(
            sourceIdentifier: sourceIdentifier,
            title: "Updated",
            notes: "New details",
            scheduledDate: Date(timeIntervalSince1970: 300),
            endDate: Date(timeIntervalSince1970: 500),
            isAllDay: false
        )

        _ = try CalendarImportPersistence.importDraft(first, in: context)
        let updated = try CalendarImportPersistence.importDraft(
            second,
            in: context
        )
        let events = try context.fetch(FetchDescriptor<Event>())

        #expect(events.count == 1)
        #expect(updated.title == "Updated")
        #expect(updated.notes == "New details")
        #expect(updated.scheduledDate == second.scheduledDate)
        #expect(updated.endDate == second.endDate)
        #expect(updated.calendarIdentifier == sourceIdentifier)
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
}
