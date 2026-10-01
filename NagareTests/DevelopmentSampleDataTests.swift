import Foundation
import SwiftData
import Testing
@testable import Nagare

@MainActor
struct DevelopmentSampleDataTests {
    @Test func fixturesPersistUntilExplicitlyRemoved() throws {
        let container = try makeContainer()
        let context = ModelContext(container)
        let date = Date(timeIntervalSince1970: 1_800_000_000)
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!

        let unrelatedProject = Project(
            title: "Keep project",
            order: "a",
            createdAt: date
        )
        let unrelatedTodo = Todo(
            title: "Keep todo",
            scheduledDate: date,
            order: "a"
        )
        let unrelatedTimedTodo = Todo(
            title: "Keep timed todo",
            scheduledDate: date,
            includesTime: true,
            order: "b"
        )
        let unrelatedRule = try RecurrenceRule.relative(every: 1, unit: .day)
        let unrelatedTemplate = RecurrenceTemplate(
            title: "Keep repeat",
            notes: nil,
            rule: unrelatedRule,
            currentItemID: unrelatedTodo.id,
            createdAt: date
        )
        context.insert(unrelatedProject)
        context.insert(unrelatedTodo)
        context.insert(unrelatedTimedTodo)
        context.insert(unrelatedTemplate)
        try context.save()

        try DevelopmentSampleData.seedIfNeeded(
            in: context,
            arguments: ["--seed-development-sample-data"],
            now: date,
            calendar: calendar
        )
        #expect(try context.fetchCount(FetchDescriptor<Project>()) == 4)
        #expect(try context.fetchCount(FetchDescriptor<Todo>()) == 17)
        #expect(try context.fetchCount(FetchDescriptor<Event>()) == 0)
        #expect(
            try context.fetchCount(FetchDescriptor<RecurrenceTemplate>()) == 4
        )

        try DevelopmentSampleData.seedIfNeeded(
            in: context,
            arguments: [],
            now: date,
            calendar: calendar
        )

        #expect(try context.fetchCount(FetchDescriptor<Project>()) == 4)
        #expect(try context.fetchCount(FetchDescriptor<Todo>()) == 17)
        #expect(
            try context.fetchCount(FetchDescriptor<RecurrenceTemplate>()) == 4
        )

        try DevelopmentSampleData.seedIfNeeded(
            in: context,
            arguments: ["--remove-development-sample-data"],
            now: date,
            calendar: calendar
        )

        #expect(try context.fetch(FetchDescriptor<Project>()).map(\.id) == [
            unrelatedProject.id
        ])
        #expect(
            Set(try context.fetch(FetchDescriptor<Todo>()).map(\.id)) == [
                unrelatedTodo.id,
                unrelatedTimedTodo.id
            ]
        )
        #expect(try context.fetch(FetchDescriptor<Event>()).isEmpty)
        #expect(
            try context.fetch(FetchDescriptor<RecurrenceTemplate>()).map(\.id)
                == [unrelatedTemplate.id]
        )
    }

    @Test func replacementKeepsOnlyFreshFixtures() throws {
        let container = try makeContainer()
        let context = ModelContext(container)
        let date = Date(timeIntervalSince1970: 1_800_000_000)
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!

        context.insert(
            Project(title: "Remove project", order: "a", createdAt: date)
        )
        context.insert(
            Todo(title: "Remove todo", scheduledDate: date, order: "a")
        )
        context.insert(
            Event(title: "Remove event", scheduledDate: date, order: "a")
        )
        try context.save()

        try DevelopmentSampleData.seedIfNeeded(
            in: context,
            arguments: ["--replace-with-development-sample-data"],
            now: date,
            calendar: calendar
        )

        #expect(try context.fetchCount(FetchDescriptor<Project>()) == 3)
        #expect(try context.fetchCount(FetchDescriptor<Todo>()) == 15)
        #expect(try context.fetchCount(FetchDescriptor<Event>()) == 0)
        #expect(
            try context.fetchCount(FetchDescriptor<RecurrenceTemplate>()) == 3
        )
        #expect(
            try context.fetch(FetchDescriptor<Project>()).allSatisfy {
                $0.title != "Remove project"
            }
        )
        #expect(
            try context.fetch(FetchDescriptor<Todo>()).allSatisfy {
                $0.title != "Remove todo"
            }
        )

        let nextDay = try #require(calendar.date(byAdding: .day, value: 1, to: date))
        try DevelopmentSampleData.seedIfNeeded(
            in: context,
            arguments: ["--replace-with-development-sample-data"],
            now: nextDay,
            calendar: calendar
        )
        #expect(try context.fetchCount(FetchDescriptor<Project>()) == 3)
        #expect(try context.fetchCount(FetchDescriptor<Todo>()) == 15)
        #expect(try context.fetchCount(FetchDescriptor<RecurrenceTemplate>()) == 3)
        let replacement = try #require(
            try context.fetch(FetchDescriptor<Todo>()).first { $0.title == "Water the balcony plants" }
        )
        #expect(replacement.scheduledDate == calendar.startOfDay(for: nextDay))
    }

    @Test func fixedReferenceProducesMatchingFixturesAndFreshSyncRevisions() throws {
        let firstContainer = try makeContainer()
        let secondContainer = try makeContainer()
        let reference = try #require(ISO8601DateFormatter().date(from: "2026-10-01T21:00:00Z"))
        let firstRevision = reference.addingTimeInterval(60)
        let secondRevision = reference.addingTimeInterval(3_600)
        let arguments = [
            "--seed-development-sample-data",
            "--development-sample-reference=2026-10-01T21:00:00Z",
            "--development-sample-time-zone=America/Los_Angeles"
        ]
        var otherCalendar = Calendar(identifier: .japanese)
        otherCalendar.timeZone = try #require(TimeZone(identifier: "Asia/Tokyo"))
        try DevelopmentSampleData.seedIfNeeded(
            in: ModelContext(firstContainer), arguments: arguments, now: firstRevision
        )
        try DevelopmentSampleData.seedIfNeeded(
            in: ModelContext(secondContainer), arguments: arguments,
            now: secondRevision, calendar: otherCalendar
        )
        let firstRepository = SwiftDataNagareRepository(modelContainer: firstContainer)
        let first = try firstRepository.load()
        let second = try SwiftDataNagareRepository(modelContainer: secondContainer).load()

        #expect(NagareDataArchive(snapshot: first, exportedAt: reference)
            == NagareDataArchive(snapshot: second, exportedAt: reference))
        #expect(first.projects.allSatisfy { $0.syncRecordID == $0.id && $0.modifiedAt == firstRevision })
        #expect(first.todos.allSatisfy { $0.syncRecordID == $0.id && $0.modifiedAt == firstRevision })
        #expect(first.recurrenceTemplates.allSatisfy { $0.syncRecordID == $0.id && $0.modifiedAt == firstRevision })
        #expect(second.projects.allSatisfy { $0.modifiedAt == secondRevision })
        let regularRepeat = try #require(first.todos.first { $0.title == "Water the balcony plants" })
        let projectID = try #require(regularRepeat.projectID)
        #expect(first.projectsByID[projectID]?.isPriority == false)
        #expect(regularRepeat.recurrenceTemplateID != nil)

        try DevelopmentSampleData.seedIfNeeded(
            in: ModelContext(firstContainer), arguments: arguments, now: secondRevision
        )
        #expect(try firstRepository.load() == first)
    }

    @Test func invalidReferenceDoesNotRemoveExistingData() throws {
        let container = try makeContainer()
        let context = ModelContext(container)
        let project = Project(title: "Keep project", order: "a")
        context.insert(project)
        try context.save()

        #expect(throws: (any Error).self) {
            try DevelopmentSampleData.seedIfNeeded(
                in: context,
                arguments: [
                    "--replace-with-development-sample-data",
                    "--development-sample-reference=invalid",
                    "--development-sample-time-zone=America/Los_Angeles"
                ]
            )
        }
        #expect(try context.fetch(FetchDescriptor<Project>()).map(\.id) == [project.id])
        #expect(!context.hasChanges)
    }

    @Test func failedReplacementRollsBackToExistingData() throws {
        let directory = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let url = directory.appending(path: "samples.store")
        let originalID = UUID()
        do {
            let writable = try makeContainer(url: url)
            let context = ModelContext(writable)
            context.insert(Project(id: originalID, title: "Keep project", order: "a"))
            try context.save()
        }
        let readOnly = try makeContainer(url: url, allowsSave: false)
        let context = ModelContext(readOnly)
        context.autosaveEnabled = false

        #expect(throws: (any Error).self) {
            try DevelopmentSampleData.seedIfNeeded(
                in: context, arguments: ["--replace-with-development-sample-data"]
            )
        }
        #expect(!context.hasChanges)
        #expect(try context.fetch(FetchDescriptor<Project>()).map(\.id) == [originalID])
        #expect(try context.fetch(FetchDescriptor<Todo>()).isEmpty)
        #expect(try context.fetch(FetchDescriptor<RecurrenceTemplate>()).isEmpty)
    }

    private func makeContainer(url: URL? = nil, allowsSave: Bool = true) throws -> ModelContainer {
        let configuration: ModelConfiguration
        if let url {
            configuration = ModelConfiguration(
                schema: NagareSchema.current, url: url,
                allowsSave: allowsSave, cloudKitDatabase: .none
            )
        } else {
            configuration = ModelConfiguration(
                schema: NagareSchema.current, isStoredInMemoryOnly: true,
                cloudKitDatabase: .none
            )
        }
        return try ModelContainer(
            for: NagareSchema.current,
            configurations: configuration
        )
    }
}
