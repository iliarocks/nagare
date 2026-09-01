import Foundation
import Testing
@testable import Nagare

struct NagareDataArchiveTests {
    private let day = Date(timeIntervalSince1970: 1_800_000_000)

    @Test func codecRoundTripsEveryArchivedField() throws {
        let projectID = UUID()
        let todoID = UUID()
        let timedTodoID = UUID()
        let templateID = UUID()
        let snapshot = NagareDataSnapshot(
            projects: [
                ProjectRecordSnapshot(
                    id: projectID,
                    syncRecordID: UUID(),
                    createdAt: day,
                    modifiedAt: day,
                    title: "Project",
                    notes: "Project notes",
                    priority: .low,
                    order: "a"
                )
            ],
            todos: [
                TodoRecordSnapshot(
                    id: todoID,
                    syncRecordID: UUID(),
                    createdAt: day,
                    modifiedAt: day,
                    title: "Todo",
                    notes: "Todo notes",
                    scheduledDate: day,
                    includesTime: false,
                    endDate: nil,
                    calendarIdentifier: nil,
                    completedAt: day.addingTimeInterval(3_600),
                    order: "b",
                    projectOrder: "c",
                    recurrenceSequence: 4,
                    recurrenceTemplateID: templateID,
                    projectID: projectID
                ),
                TodoRecordSnapshot(
                    id: timedTodoID,
                    syncRecordID: UUID(),
                    createdAt: day,
                    modifiedAt: day,
                    title: "Timed Todo",
                    notes: "Timed Todo notes",
                    scheduledDate: day,
                    includesTime: true,
                    endDate: day.addingTimeInterval(1_800),
                    calendarIdentifier: "calendar-event-id",
                    completedAt: nil,
                    order: "d",
                    projectOrder: "e",
                    recurrenceSequence: nil,
                    recurrenceTemplateID: nil,
                    projectID: projectID
                )
            ],
            recurrenceTemplates: [
                RecurrenceTemplateRecordSnapshot(
                    id: templateID,
                    syncRecordID: UUID(),
                    createdAt: day,
                    modifiedAt: day,
                    title: "Repeat",
                    notes: "Repeat notes",
                    modeRawValue: RecurrenceMode.relative.rawValue,
                    unitRawValue: RecurrenceUnit.day.rawValue,
                    interval: 2,
                    anchors: [],
                    reference: nil,
                    repeatUntil: day,
                    startTimeSeconds: nil,
                    endTimeSeconds: nil,
                    currentItemID: todoID,
                    currentSequence: 4,
                    currentScheduledDate: day,
                    projectID: projectID
                )
            ]
        )

        let data = try NagareDataArchiveCodec.encode(
            snapshot,
            exportedAt: day
        )
        let decoded = try NagareDataArchiveCodec.decode(data)

        #expect(decoded == NagareDataArchive(snapshot: snapshot, exportedAt: day))
        let json = try #require(String(data: data, encoding: .utf8))
        #expect(!json.contains("syncRecordID"))
        #expect(!json.contains("modifiedAt"))
        #expect(json.contains("calendar-event-id"))
        #expect(json.contains("repeatUntil"))
        #expect(decoded.projects.first?.priority == .low)
    }

    @Test func decoderTreatsMissingRepeatUntilAsIndefinite() throws {
        let templateID = UUID()
        let json = """
        {
          "formatVersion": 2,
          "exportedAt": "2027-01-01T00:00:00Z",
          "projects": [],
          "todos": [],
          "recurrenceTemplates": [
            {
              "id": "\(templateID.uuidString)",
              "createdAt": "2027-01-01T00:00:00Z",
              "title": "Legacy repeat",
              "modeRawValue": "relative",
              "unitRawValue": "day",
              "interval": 1,
              "anchors": [],
              "currentItemID": "\(UUID().uuidString)",
              "currentSequence": 0
            }
          ]
        }
        """

        let archive = try NagareDataArchiveCodec.decode(Data(json.utf8))

        #expect(archive.recurrenceTemplates.first?.repeatUntil == nil)
    }

    @Test func decoderRejectsUnsupportedVersionsBeforeReadingPayload() {
        let data = Data(#"{"formatVersion": 99}"#.utf8)

        #expect(throws: NagareDataArchiveError.unsupportedVersion(99)) {
            try NagareDataArchiveCodec.decode(data)
        }
    }

    @Test func decoderConvertsLegacyEventsIntoTimedTodos() throws {
        let eventID = UUID()
        let start = "2027-01-15T18:30:00Z"
        let end = "2027-01-15T19:45:00Z"
        let json = """
        {
          "formatVersion": 1,
          "exportedAt": "2027-01-01T00:00:00Z",
          "projects": [],
          "todos": [],
          "events": [
            {
              "id": "\(eventID.uuidString)",
              "createdAt": "2027-01-01T00:00:00Z",
              "title": "Dinner",
              "notes": "Reservation for two",
              "scheduledDate": "\(start)",
              "endDate": "\(end)",
              "calendarIdentifier": "legacy-id",
              "order": "i"
            }
          ],
          "recurrenceTemplates": []
        }
        """

        let archive = try NagareDataArchiveCodec.decode(Data(json.utf8))
        let todo = try #require(archive.todos.first)

        #expect(archive.formatVersion == NagareDataArchive.currentFormatVersion)
        #expect(archive.todos.count == 1)
        #expect(todo.id == eventID)
        #expect(todo.title == "Dinner")
        #expect(todo.notes == "Reservation for two")
        #expect(todo.includesTime)
        #expect(todo.endDate?.timeIntervalSince(todo.scheduledDate) == 4_500)
        #expect(todo.calendarIdentifier == "legacy-id")
        #expect(todo.completedAt == nil)
    }

    @Test func plannerRejectsDuplicateSemanticIDs() {
        let project = NagareArchiveProject(
            id: UUID(),
            createdAt: day,
            title: "Project",
            notes: nil,
            isPriority: false,
            order: "a"
        )
        let archive = NagareDataArchive(
            exportedAt: day,
            projects: [project, project],
            todos: [],
            recurrenceTemplates: []
        )

        #expect(throws: NagareDataArchiveError.self) {
            try NagareDataArchivePlanner.planImport(
                archive,
                into: .empty,
                calendar: calendar
            )
        }
    }

    @Test func plannerValidatesRelationshipsAndPreviewsMerge() throws {
        let projectID = UUID()
        let todoID = UUID()
        let templateID = UUID()
        let archive = archive(
            projectID: projectID,
            todoID: todoID,
            templateID: templateID
        )
        let current = NagareDataSnapshot(
            projects: [],
            todos: [todoSnapshot(id: todoID)],
            recurrenceTemplates: []
        )

        let plan = try NagareDataArchivePlanner.planImport(
            archive,
            into: current,
            calendar: calendar
        )

        #expect(plan.summary.totalCount == 3)
        #expect(plan.summary.createdCount == 2)
        #expect(plan.summary.updatedCount == 1)
        #expect(plan.recurrenceTemplates.first?.rule.interval == 1)

        let broken = NagareDataArchive(
            exportedAt: day,
            projects: [],
            todos: archive.todos,
            recurrenceTemplates: archive.recurrenceTemplates
        )
        #expect(throws: NagareDataArchiveError.self) {
            try NagareDataArchivePlanner.planImport(
                broken,
                into: .empty,
                calendar: calendar
            )
        }
    }

    private var calendar: Calendar {
        var value = Calendar(identifier: .gregorian)
        value.timeZone = TimeZone(secondsFromGMT: 0)!
        return value
    }

    private func archive(
        projectID: UUID,
        todoID: UUID,
        templateID: UUID
    ) -> NagareDataArchive {
        NagareDataArchive(
            exportedAt: day,
            projects: [
                NagareArchiveProject(
                    id: projectID,
                    createdAt: day,
                    title: "Project",
                    notes: nil,
                    isPriority: false,
                    order: "a"
                )
            ],
            todos: [
                NagareArchiveTodo(
                    id: todoID,
                    createdAt: day,
                    title: "Todo",
                    notes: nil,
                    scheduledDate: day,
                    completedAt: nil,
                    order: "a",
                    projectOrder: "a",
                    recurrenceSequence: 0,
                    recurrenceTemplateID: templateID,
                    projectID: projectID
                )
            ],
            recurrenceTemplates: [
                NagareArchiveRecurrenceTemplate(
                    id: templateID,
                    createdAt: day,
                    title: "Repeat",
                    notes: nil,
                    modeRawValue: RecurrenceMode.relative.rawValue,
                    unitRawValue: RecurrenceUnit.day.rawValue,
                    interval: 1,
                    anchors: [],
                    reference: nil,
                    startTimeSeconds: nil,
                    endTimeSeconds: nil,
                    currentItemID: todoID,
                    currentSequence: 0,
                    projectID: projectID
                )
            ]
        )
    }

    private func todoSnapshot(id: UUID) -> TodoRecordSnapshot {
        TodoRecordSnapshot(
            id: id,
            syncRecordID: id,
            createdAt: day,
            modifiedAt: nil,
            title: "Existing",
            notes: nil,
            scheduledDate: day,
            includesTime: false,
            endDate: nil,
            calendarIdentifier: nil,
            completedAt: nil,
            order: "a",
            projectOrder: nil,
            recurrenceSequence: nil,
            recurrenceTemplateID: nil,
            projectID: nil
        )
    }
}
