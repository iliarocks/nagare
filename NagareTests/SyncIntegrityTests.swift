import CoreData
import Foundation
import SwiftData
import Testing
@testable import Nagare

@MainActor
struct SyncIntegrityTests {
    @Test func iCloudSyncIsStrictlyOptIn() throws {
        let suiteName = "NagareCloudPreferencesTests-\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suiteName))
        defer { defaults.removePersistentDomain(forName: suiteName) }

        defaults.removePersistentDomain(forName: suiteName)
        #expect(!NagareCloudPreferences.isSyncEnabled(in: defaults))

        defaults.set(
            true,
            forKey: NagareCloudPreferences.syncEnabledKey
        )
        #expect(NagareCloudPreferences.isSyncEnabled(in: defaults))
        #expect(
            NagareCloudPreferences.shouldEnableSync(
                arguments: [],
                defaults: defaults
            )
        )
        #expect(
            !NagareCloudPreferences.shouldEnableSync(
                arguments: ["--use-reorder-ui-test-store"],
                defaults: defaults
            )
        )
    }

    @Test func cloudSchemaSatisfiesEveryStructuralRequirement() throws {
        let managedModel = try #require(
            NSManagedObjectModel.makeManagedObjectModel(
                for: NagareSchema.current
            )
        )

        for entity in managedModel.entities {
            #expect(entity.uniquenessConstraints.isEmpty)
            for attribute in entity.attributesByName.values {
                #expect(attribute.isOptional || attribute.defaultValue != nil)
            }
            for relationship in entity.relationshipsByName.values {
                #expect(relationship.isOptional)
                #expect(relationship.inverseRelationship != nil)
                #expect(relationship.deleteRule != .denyDeleteRule)
            }
        }
    }

    @Test func versionOneStoreMigratesWithoutLosingValuesOrRelationships() throws {
        let storeURL = temporaryStoreURL()
        defer { removeStoreFiles(at: storeURL) }

        let projectID = UUID()
        let todoID = UUID()
        let templateID = UUID()
        let createdAt = Date(timeIntervalSince1970: 1_750_000_000)

        try autoreleasepool {
            let oldSchema = Schema(versionedSchema: NagareSchemaV1.self)
            let oldConfiguration = ModelConfiguration(
                "MigrationV1",
                schema: oldSchema,
                url: storeURL,
                cloudKitDatabase: .none
            )
            let oldContainer = try ModelContainer(
                for: oldSchema,
                configurations: oldConfiguration
            )
            let context = oldContainer.mainContext

            let project = NagareSchemaV1.Project(
                id: projectID,
                title: "Original project",
                notes: "Preserve me",
                isPriority: true,
                order: "i",
                createdAt: createdAt
            )
            let todo = NagareSchemaV1.Todo(
                id: todoID,
                title: "Original todo",
                notes: "Still here",
                scheduledDate: createdAt,
                createdAt: createdAt,
                order: "r",
                projectOrder: "f"
            )
            let template = NagareSchemaV1.RecurrenceTemplate(
                id: templateID,
                itemTypeRawValue: "todo",
                title: "Future todo",
                notes: "Future notes",
                modeRawValue: "relative",
                unitRawValue: "day",
                interval: 2,
                currentItemID: todoID,
                createdAt: createdAt
            )
            todo.project = project
            todo.recurrenceSequence = 0
            todo.recurrenceTemplate = template
            template.project = project
            context.insert(project)
            context.insert(todo)
            context.insert(template)
            try context.save()
        }

        let configuration = ModelConfiguration(
            "MigrationV2",
            schema: NagareSchema.current,
            url: storeURL,
            cloudKitDatabase: .none
        )
        let container = try ModelContainer(
            for: NagareSchema.current,
            migrationPlan: NagareMigrationPlan.self,
            configurations: configuration
        )
        let context = container.mainContext

        let project = try #require(
            context.fetch(FetchDescriptor<Project>()).first
        )
        let todo = try #require(
            context.fetch(FetchDescriptor<Todo>()).first
        )
        let template = try #require(
            context.fetch(FetchDescriptor<RecurrenceTemplate>()).first
        )

        #expect(project.id == projectID)
        #expect(project.title == "Original project")
        #expect(project.notes == "Preserve me")
        #expect(project.isPriority)
        #expect(project.createdAt == createdAt)
        #expect(project.modifiedAt == nil)
        #expect(project.syncRecordID == nil)
        #expect(project.todos.map(\.id) == [todoID])
        #expect(project.recurrenceTemplates.map(\.id) == [templateID])

        #expect(todo.id == todoID)
        #expect(todo.notes == "Still here")
        #expect(todo.project?.id == projectID)
        #expect(todo.recurrenceTemplate?.id == templateID)
        #expect(todo.recurrenceSequence == 0)
        #expect(todo.modifiedAt == nil)
        #expect(todo.syncRecordID == nil)

        #expect(template.id == templateID)
        #expect(template.currentItemID == todoID)
        #expect(template.todoOccurrences.map(\.id) == [todoID])
        #expect(template.project?.id == projectID)
        #expect(template.modifiedAt == nil)
        #expect(template.syncRecordID == nil)
    }

    @Test func originalUnversionedStoreIsRecognizedAsVersionOne() throws {
        let storeURL = temporaryStoreURL()
        defer { removeStoreFiles(at: storeURL) }

        let projectID = UUID()

        try autoreleasepool {
            // This is how the released app created its store before it had a
            // migration plan. It deliberately does not use
            // Schema(versionedSchema:).
            let originalSchema = Schema(NagareSchemaV1.models)
            let oldConfiguration = ModelConfiguration(
                "OriginalUnversionedStore",
                schema: originalSchema,
                url: storeURL,
                cloudKitDatabase: .none
            )
            let oldContainer = try ModelContainer(
                for: originalSchema,
                configurations: oldConfiguration
            )
            let context = oldContainer.mainContext
            context.insert(
                NagareSchemaV1.Project(
                    id: projectID,
                    title: "From the released app",
                    order: "i"
                )
            )
            try context.save()
        }

        let currentConfiguration = ModelConfiguration(
            "CurrentStore",
            schema: NagareSchema.current,
            url: storeURL,
            cloudKitDatabase: .none
        )
        let container = try ModelContainer(
            for: NagareSchema.current,
            migrationPlan: NagareMigrationPlan.self,
            configurations: currentConfiguration
        )
        let projects = try container.mainContext.fetch(
            FetchDescriptor<Project>()
        )

        #expect(projects.map(\.id) == [projectID])
        #expect(projects.first?.title == "From the released app")
        #expect(projects.first?.modifiedAt == nil)
        #expect(projects.first?.syncRecordID == nil)
    }

    @Test func transactionStampsEveryChangedRecordAtOneBoundary() throws {
        let context = try makeContext()
        let createdAt = Date(timeIntervalSince1970: 1_700_000_000)
        let modifiedAt = createdAt.addingTimeInterval(60)
        let project = Project(
            title: "Project",
            order: "i",
            createdAt: createdAt
        )
        let todo = Todo(
            title: "Todo",
            scheduledDate: createdAt,
            createdAt: createdAt,
            order: "i"
        )
        todo.project = project
        context.insert(project)
        context.insert(todo)

        try SwiftDataTransaction.save(context, at: modifiedAt)

        #expect(project.modifiedAt == modifiedAt)
        #expect(todo.modifiedAt == modifiedAt)
    }

    @Test func duplicateSemanticIDsConvergeToNewestRecord() throws {
        let context = try makeContext()
        let sharedID = UUID()
        let older = Todo(
            id: sharedID,
            title: "Older",
            scheduledDate: .now,
            createdAt: Date(timeIntervalSince1970: 100),
            order: "i"
        )
        let newer = Todo(
            id: sharedID,
            title: "Newer",
            scheduledDate: .now,
            createdAt: Date(timeIntervalSince1970: 200),
            order: "i"
        )
        older.modifiedAt = Date(timeIntervalSince1970: 300)
        newer.modifiedAt = Date(timeIntervalSince1970: 400)
        context.insert(older)
        context.insert(newer)

        let report = try SyncIntegrityRepair.repair(in: context)
        let saved = try context.fetch(FetchDescriptor<Todo>())

        #expect(report.duplicateTodosRemoved == 1)
        #expect(saved.count == 1)
        #expect(saved.first?.id == sharedID)
        #expect(saved.first?.title == "Newer")
    }

    @Test func exactTimestampTiesUseReplicatedPhysicalIdentity() throws {
        let context = try makeContext()
        let semanticID = UUID()
        let timestamp = Date(timeIntervalSince1970: 1_750_000_000)
        let lowerSyncID = UUID(
            uuidString: "00000000-0000-0000-0000-000000000001"
        )!
        let higherSyncID = UUID(
            uuidString: "00000000-0000-0000-0000-000000000002"
        )!
        let lower = Todo(
            id: semanticID,
            title: "Lower physical identity",
            scheduledDate: timestamp,
            createdAt: timestamp,
            order: "i"
        )
        let higher = Todo(
            id: semanticID,
            title: "Higher physical identity",
            scheduledDate: timestamp,
            createdAt: timestamp,
            order: "i"
        )
        lower.modifiedAt = timestamp
        lower.syncRecordID = lowerSyncID
        higher.modifiedAt = timestamp
        higher.syncRecordID = higherSyncID
        context.insert(lower)
        context.insert(higher)

        _ = try SyncIntegrityRepair.repair(in: context)
        let saved = try context.fetch(FetchDescriptor<Todo>())

        #expect(saved.count == 1)
        #expect(saved.first?.title == "Higher physical identity")
        #expect(saved.first?.syncRecordID == higherSyncID)
    }

    @Test func deduplicationReconnectsEveryOwnedRelationship() throws {
        let context = try makeContext()
        let timestamp = Date(timeIntervalSince1970: 1_750_000_000)
        let projectID = UUID()
        let templateID = UUID()

        let olderProject = Project(
            id: projectID,
            title: "Older project",
            order: "i",
            createdAt: timestamp
        )
        let newerProject = Project(
            id: projectID,
            title: "Newer project",
            order: "i",
            createdAt: timestamp
        )
        olderProject.modifiedAt = timestamp
        newerProject.modifiedAt = timestamp.addingTimeInterval(1)

        let rule = try RecurrenceRule.relative(every: 1, unit: .day)
        let todo = Todo(
            title: "Attached todo",
            scheduledDate: timestamp,
            order: "i"
        )
        let event = Event(
            title: "Attached event",
            scheduledDate: timestamp,
            order: "i"
        )
        let olderTemplate = RecurrenceTemplate(
            id: templateID,
            itemType: .todo,
            title: "Older template",
            notes: nil,
            rule: rule,
            currentItemID: todo.id,
            createdAt: timestamp
        )
        let newerTemplate = RecurrenceTemplate(
            id: templateID,
            itemType: .todo,
            title: "Newer template",
            notes: nil,
            rule: rule,
            currentItemID: todo.id,
            createdAt: timestamp
        )
        olderTemplate.modifiedAt = timestamp
        newerTemplate.modifiedAt = timestamp.addingTimeInterval(1)
        // The older client must preserve a future item kind while still
        // reconnecting its relationships during semantic-ID deduplication.
        olderTemplate.itemTypeRawValue = "future-item"
        newerTemplate.itemTypeRawValue = "future-item"

        todo.project = olderProject
        todo.recurrenceTemplate = olderTemplate
        event.project = olderProject
        olderTemplate.project = olderProject
        newerTemplate.project = newerProject

        context.insert(olderProject)
        context.insert(newerProject)
        context.insert(olderTemplate)
        context.insert(newerTemplate)
        context.insert(todo)
        context.insert(event)

        let report = try SyncIntegrityRepair.repair(in: context)
        let projects = try context.fetch(FetchDescriptor<Project>())
        let templates = try context.fetch(
            FetchDescriptor<RecurrenceTemplate>()
        )

        #expect(report.duplicateProjectsRemoved == 1)
        #expect(report.duplicateTemplatesRemoved == 1)
        #expect(projects.count == 1)
        #expect(projects.first === newerProject)
        #expect(todo.project === newerProject)
        #expect(event.project === newerProject)
        #expect(templates.count == 1)
        #expect(templates.first === newerTemplate)
        #expect(todo.recurrenceTemplate === newerTemplate)
        #expect(newerTemplate.project === newerProject)
    }

    @Test func migratedRecordsReceiveOneStablePhysicalIdentity() throws {
        let context = try makeContext()
        let todo = Todo(
            title: "Migrated",
            scheduledDate: .now,
            order: "i"
        )
        todo.syncRecordID = nil
        context.insert(todo)

        let firstReport = try SyncIntegrityRepair.repair(in: context)
        let assignedID = try #require(todo.syncRecordID)
        let secondReport = try SyncIntegrityRepair.repair(in: context)

        #expect(firstReport.syncRecordIDsAssigned == 1)
        #expect(secondReport.syncRecordIDsAssigned == 0)
        #expect(todo.syncRecordID == assignedID)
    }

    @Test func concurrentRecurringTodoSuccessorsConvergeToTemplatePointer() throws {
        let context = try makeContext()
        let day = Date(timeIntervalSince1970: 1_750_000_000)
        let original = Todo(
            title: "Original",
            scheduledDate: day,
            completedAt: day,
            createdAt: day,
            order: "i"
        )
        original.recurrenceSequence = 0
        let rule = try RecurrenceRule.relative(every: 1, unit: .day)
        let template = RecurrenceTemplate(
            itemType: .todo,
            title: "Repeating",
            notes: nil,
            rule: rule,
            currentItemID: original.id,
            createdAt: day
        )
        original.recurrenceTemplate = template

        let firstSuccessor = Todo(
            title: "First device",
            scheduledDate: day.addingTimeInterval(86_400),
            createdAt: day.addingTimeInterval(1),
            order: "i"
        )
        firstSuccessor.recurrenceSequence = 1
        firstSuccessor.recurrenceTemplate = template
        let secondSuccessor = Todo(
            title: "Second device",
            scheduledDate: day.addingTimeInterval(86_400),
            createdAt: day.addingTimeInterval(2),
            order: "i"
        )
        secondSuccessor.recurrenceSequence = 1
        secondSuccessor.recurrenceTemplate = template
        template.currentSequence = 1
        template.currentItemID = firstSuccessor.id

        context.insert(template)
        context.insert(original)
        context.insert(firstSuccessor)
        context.insert(secondSuccessor)

        let report = try SyncIntegrityRepair.repair(in: context)
        let active = try context.fetch(FetchDescriptor<Todo>())
            .filter { $0.completedAt == nil }

        #expect(report.recurrenceConflictsRepaired == 1)
        #expect(active.map(\.id) == [firstSuccessor.id])
        #expect(template.currentSequence == 1)
        #expect(template.currentItemID == firstSuccessor.id)
    }

    @Test func eventRecurrenceKeepsOnlyHighestAvailableSequence() throws {
        let context = try makeContext()
        let day = Date(timeIntervalSince1970: 1_750_000_000)
        let first = Event(
            title: "First",
            scheduledDate: day,
            createdAt: day,
            order: "i"
        )
        first.recurrenceSequence = 0
        let rule = try RecurrenceRule.absolute(
            every: 1,
            unit: .day,
            reference: day,
            calendar: calendar
        )
        let template = RecurrenceTemplate(
            itemType: .event,
            title: "Event",
            notes: nil,
            rule: rule,
            startTimeSeconds: 0,
            currentItemID: first.id,
            createdAt: day
        )
        first.recurrenceTemplate = template

        let second = Event(
            title: "Second",
            scheduledDate: day.addingTimeInterval(86_400),
            createdAt: day.addingTimeInterval(1),
            order: "i"
        )
        second.recurrenceSequence = 1
        second.recurrenceTemplate = template
        context.insert(template)
        context.insert(first)
        context.insert(second)

        _ = try SyncIntegrityRepair.repair(in: context)
        let events = try context.fetch(FetchDescriptor<Event>())

        #expect(events.map(\.id) == [second.id])
        #expect(template.currentSequence == 1)
        #expect(template.currentItemID == second.id)
    }

    private var calendar: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        return calendar
    }

    private func makeContext() throws -> ModelContext {
        let configuration = ModelConfiguration(
            schema: NagareSchema.current,
            isStoredInMemoryOnly: true,
            cloudKitDatabase: .none
        )
        let container = try ModelContainer(
            for: NagareSchema.current,
            migrationPlan: NagareMigrationPlan.self,
            configurations: configuration
        )
        let context = ModelContext(container)
        context.autosaveEnabled = false
        return context
    }

    private func temporaryStoreURL() -> URL {
        FileManager.default.temporaryDirectory
            .appending(path: "NagareMigration-\(UUID().uuidString).store")
    }

    private func removeStoreFiles(at url: URL) {
        for suffix in ["", "-wal", "-shm"] {
            try? FileManager.default.removeItem(
                at: URL(filePath: url.path + suffix)
            )
        }
    }
}
