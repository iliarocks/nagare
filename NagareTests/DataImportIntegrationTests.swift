import Foundation
import SwiftData
import Testing
@testable import Nagare

@MainActor
struct DataImportIntegrationTests {
    private let day = Date(timeIntervalSince1970: 1_800_000_000)

    @Test func importMergesAtomicallyAndRestoresRelationships() throws {
        let container = try makeContainer()
        let context = ModelContext(container)
        let projectID = UUID()
        let todoID = UUID()
        let eventID = UUID()
        let templateID = UUID()
        let unrelatedID = UUID()
        let existingTodo = Todo(
            id: todoID,
            title: "Old title",
            scheduledDate: day,
            order: "z"
        )
        let existingPhysicalID = existingTodo.syncRecordID
        context.insert(existingTodo)
        context.insert(
            Todo(
                id: unrelatedID,
                title: "Local only",
                scheduledDate: day,
                order: "y"
            )
        )
        try context.save()

        let repository = SwiftDataNagareRepository(modelContainer: container)
        let archive = makeArchive(
            projectID: projectID,
            todoID: todoID,
            eventID: eventID,
            templateID: templateID
        )
        let plan = try NagareDataArchivePlanner.planImport(
            archive,
            into: repository.load(),
            calendar: calendar
        )

        #expect(plan.summary.createdCount == 3)
        #expect(plan.summary.updatedCount == 1)
        try repository.importData(plan, at: day.addingTimeInterval(60))

        var snapshot = try repository.load()
        #expect(snapshot.projects.count == 1)
        #expect(snapshot.projectsByID[projectID]?.priority == .normal)
        #expect(snapshot.todos.count == 3)
        #expect(snapshot.recurrenceTemplates.count == 1)
        #expect(snapshot.todosByID[unrelatedID]?.title == "Local only")
        #expect(snapshot.todosByID[todoID]?.title == "Imported todo")
        #expect(snapshot.todosByID[todoID]?.projectID == projectID)
        #expect(snapshot.todosByID[todoID]?.recurrenceTemplateID == templateID)
        #expect(snapshot.todosByID[todoID]?.syncRecordID == existingPhysicalID)
        #expect(snapshot.todosByID[eventID]?.projectID == projectID)
        #expect(
            snapshot.todosByID[eventID]?.calendarIdentifier
                == "external-event"
        )
        #expect(snapshot.templatesByID[templateID]?.projectID == projectID)
        #expect(snapshot.templatesByID[templateID]?.currentItemID == todoID)

        let secondPlan = try NagareDataArchivePlanner.planImport(
            archive,
            into: snapshot,
            calendar: calendar
        )
        #expect(secondPlan.summary.createdCount == 0)
        #expect(secondPlan.summary.updatedCount == 4)
        try repository.importData(
            secondPlan,
            at: day.addingTimeInterval(120)
        )
        snapshot = try repository.load()
        #expect(snapshot.projects.count == 1)
        #expect(snapshot.todos.count == 3)
        #expect(snapshot.recurrenceTemplates.count == 1)
    }

    @Test func persistenceFailureRollsBackEarlierImportedChanges() throws {
        let container = try makeContainer()
        let context = ModelContext(container)
        let projectID = UUID()
        let duplicateTodoID = UUID()
        context.insert(Project(id: projectID, title: "Original", order: "a"))
        context.insert(
            Todo(
                id: duplicateTodoID,
                title: "Duplicate one",
                scheduledDate: day,
                order: "a"
            )
        )
        context.insert(
            Todo(
                id: duplicateTodoID,
                title: "Duplicate two",
                scheduledDate: day,
                order: "b"
            )
        )
        try context.save()

        let repository = SwiftDataNagareRepository(modelContainer: container)
        let archive = NagareDataArchive(
            exportedAt: day,
            projects: [
                NagareArchiveProject(
                    id: projectID,
                    createdAt: day,
                    title: "Imported",
                    notes: nil,
                    isPriority: true,
                    order: "z"
                )
            ],
            todos: [
                NagareArchiveTodo(
                    id: duplicateTodoID,
                    createdAt: day,
                    title: "Imported todo",
                    notes: nil,
                    scheduledDate: day,
                    includesTime: false,
                    completedAt: nil,
                    order: "c",
                    projectOrder: "a",
                    recurrenceSequence: nil,
                    recurrenceTemplateID: nil,
                    projectID: projectID
                )
            ],
            recurrenceTemplates: []
        )
        let plan = try NagareDataArchivePlanner.planImport(
            archive,
            into: repository.load(),
            calendar: calendar
        )

        #expect(throws: NagareDataPersistenceError.self) {
            try repository.importData(plan, at: day.addingTimeInterval(60))
        }
        let snapshot = try repository.load()
        #expect(snapshot.projectsByID[projectID]?.title == "Original")
        #expect(snapshot.projectsByID[projectID]?.isPriority == false)
    }

    @Test func legacyArchiveMergesLowAfterExistingAndImportedRegularProjects() throws {
        let container = try makeContainer()
        let context = ModelContext(container)
        let existing = Project(title: "Local regular", order: "z")
        let priority = Project(title: "Priority", priority: .high, order: "i")
        context.insert(existing)
        context.insert(priority)
        try context.save()
        let regularID = UUID()
        let firstLowID = UUID()
        let secondLowID = UUID()
        let json = """
        {
          "formatVersion": 2,
          "exportedAt": "2027-01-01T00:00:00Z",
          "projects": [
            {
              "id": "\(secondLowID.uuidString)",
              "createdAt": "2027-01-01T00:00:00Z",
              "title": "Second low",
              "isPriority": false,
              "priorityRawValue": 0,
              "order": "b"
            },
            {
              "id": "\(regularID.uuidString)",
              "createdAt": "2027-01-01T00:00:00Z",
              "title": "Imported regular",
              "isPriority": false,
              "priorityRawValue": 1,
              "order": "m"
            },
            {
              "id": "\(firstLowID.uuidString)",
              "createdAt": "2027-01-01T00:00:00Z",
              "title": "First low",
              "isPriority": true,
              "priorityRawValue": 0,
              "order": "a"
            }
          ],
          "todos": [],
          "recurrenceTemplates": []
        }
        """
        let archive = try NagareDataArchiveCodec.decode(Data(json.utf8))
        let repository = SwiftDataNagareRepository(modelContainer: container)
        let plan = try NagareDataArchivePlanner.planImport(
            archive, into: repository.load(), calendar: calendar
        )

        try repository.importData(plan, at: day)

        let snapshot = try repository.load()
        let regular = snapshot.projects.filter { !$0.isPriority }.sorted {
            $0.order < $1.order
        }
        #expect(regular.map(\.id) == [regularID, existing.id, firstLowID, secondLowID])
        #expect(snapshot.projectsByID[priority.id]?.priority == .high)
        #expect(snapshot.projectsByID[priority.id]?.order == "i")
        let exported = try NagareDataArchiveCodec.decode(
            NagareDataArchiveCodec.encode(snapshot, exportedAt: day)
        )
        #expect(exported.projects.allSatisfy { $0.priorityRawValue != 0 })
    }

    private var calendar: Calendar {
        var value = Calendar(identifier: .gregorian)
        value.timeZone = TimeZone(secondsFromGMT: 0)!
        return value
    }

    private func makeContainer() throws -> ModelContainer {
        let configuration = ModelConfiguration(
            schema: NagareSchema.current,
            isStoredInMemoryOnly: true,
            cloudKitDatabase: .none
        )
        return try ModelContainer(
            for: NagareSchema.current,
            configurations: configuration
        )
    }

    private func makeArchive(
        projectID: UUID,
        todoID: UUID,
        eventID: UUID,
        templateID: UUID
    ) -> NagareDataArchive {
        NagareDataArchive(
            exportedAt: day,
            projects: [
                NagareArchiveProject(
                    id: projectID,
                    createdAt: day,
                    title: "Imported project",
                    notes: "Notes",
                    isPriority: false,
                    priority: .normal,
                    order: "a"
                )
            ],
            todos: [
                NagareArchiveTodo(
                    id: todoID,
                    createdAt: day,
                    title: "Imported todo",
                    notes: "Notes",
                    scheduledDate: day,
                    completedAt: nil,
                    order: "a",
                    projectOrder: "a",
                    recurrenceSequence: 0,
                    recurrenceTemplateID: templateID,
                    projectID: projectID
                ),
                NagareArchiveTodo(
                    id: eventID,
                    createdAt: day,
                    title: "Imported timed todo",
                    notes: nil,
                    scheduledDate: day.addingTimeInterval(3_600),
                    includesTime: true,
                    endDate: day.addingTimeInterval(5_400),
                    calendarIdentifier: "external-event",
                    completedAt: nil,
                    order: "b",
                    projectOrder: "b",
                    recurrenceSequence: nil,
                    recurrenceTemplateID: nil,
                    projectID: projectID
                )
            ],
            recurrenceTemplates: [
                NagareArchiveRecurrenceTemplate(
                    id: templateID,
                    createdAt: day,
                    title: "Imported repeat",
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
}
