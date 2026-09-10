import Foundation
import SwiftData
import Testing
@testable import Nagare

@MainActor
struct UpgradePersistenceTests {
    @Test func previousStorePreservesRecordsAndRemainsEditable() throws {
        let source = try #require(Bundle(for: UpgradeFixtureBundle.self)
            .url(forResource: "PreCleanupV5", withExtension: "store"))
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let url = directory.appendingPathComponent("upgrade.store")
        try FileManager.default.copyItem(at: source, to: url)

        let container = try openStore(at: url)
        let context = ModelContext(container)
        let todos = try context.fetch(FetchDescriptor<Todo>())
        let projects = try context.fetch(FetchDescriptor<Project>())
        let templates = try context.fetch(FetchDescriptor<RecurrenceTemplate>())
        let events = try context.fetch(FetchDescriptor<Event>())
        #expect(todos.count == 3)
        #expect(projects.count == 1)
        #expect(templates.count == 1)
        #expect(events.count == 1)
        let project = try #require(projects.first)
        #expect(project.title == "Fixture project")
        #expect(project.notes == "Preserve project notes")
        let timed = try #require(todos.first { $0.title == "Fixture timed todo" })
        #expect(timed.notes == "Preserve task notes")
        #expect(timed.includesTime)
        #expect(timed.scheduledDate == Date(timeIntervalSinceReferenceDate: 800_000_000))
        #expect(timed.endDate?.timeIntervalSince(timed.scheduledDate) == 3600)
        #expect(timed.project?.id == project.id)
        #expect(timed.projectOrder == "9")
        let completed = try #require(todos.first { $0.title == "Fixture completed todo" })
        #expect(completed.completedAt == Date(timeIntervalSinceReferenceDate: 800_001_200))
        let recurring = try #require(todos.first { $0.title == "Fixture recurring todo" })
        let template = try #require(templates.first)
        #expect(recurring.recurrenceTemplate?.id == template.id)
        #expect(template.currentItemID == recurring.id)
        #expect(template.project?.id == project.id)
        #expect(try template.rule() == .relative(every: 2, unit: .day))
        #expect(events.first?.notes == "Preserve legacy record")

        let repository = SwiftDataNagareRepository(modelContainer: container)
        try repository.updateNote(.todo(timed.id), title: timed.title,
            notes: "Edited after upgrade", at: Date(timeIntervalSinceReferenceDate: 800_010_000))
        let reopened = SwiftDataNagareRepository(modelContainer: try openStore(at: url))
        #expect(try reopened.load().todosByID[timed.id]?.notes == "Edited after upgrade")
    }

    private func openStore(at url: URL) throws -> ModelContainer {
        let configuration = ModelConfiguration(schema: NagareSchema.current,
            url: url, cloudKitDatabase: .none)
        return try ModelContainer(for: NagareSchema.current, configurations: configuration)
    }
}

private final class UpgradeFixtureBundle: NSObject {}
