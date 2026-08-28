import CoreData
import Foundation
import SwiftData
import Testing
@testable import Nagare

@MainActor
struct SyncIntegrityTests {
    @Test func cloudSyncMonitorTracksSuccessAndRecoversFromErrors() {
        let monitor = NagareCloudSyncMonitor(isEnabled: true)
        defer { monitor.stop() }
        let firstID = UUID()
        let start = Date(timeIntervalSince1970: 100)
        let failureDate = start.addingTimeInterval(1)

        monitor.record(
            type: .import,
            identifier: firstID,
            startDate: start,
            endDate: nil,
            succeeded: false,
            errorDescription: nil
        )
        #expect(monitor.phase == .syncing)

        monitor.record(
            type: .import,
            identifier: firstID,
            startDate: start,
            endDate: failureDate,
            succeeded: false,
            errorDescription: "Network unavailable"
        )
        #expect(monitor.phase == .failed)
        #expect(monitor.lastErrorDescription == "Network unavailable")

        let recoveryDate = failureDate.addingTimeInterval(10)
        monitor.record(
            type: .import,
            identifier: UUID(),
            startDate: recoveryDate,
            endDate: recoveryDate,
            succeeded: true,
            errorDescription: nil
        )
        #expect(monitor.phase == .upToDate)
        #expect(monitor.lastSuccessfulImport == recoveryDate)
        #expect(monitor.lastErrorDescription == nil)

        monitor.recordHistoryObservation(
            isHealthy: false,
            errorDescription: "History unavailable"
        )
        #expect(monitor.phase == .failed)
        #expect(monitor.lastErrorDescription == "History unavailable")
        monitor.recordHistoryObservation(isHealthy: true)
        #expect(monitor.phase == .upToDate)
    }

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

#if DEBUG
    @Test func developmentSyncPreferenceDoesNotReuseReleasePreference() {
        #expect(NagareCloudPreferences.syncEnabledKey.contains("debug"))
        #expect(
            NagareCloudPreferences.syncEnabledKey
                != "nagare.iCloudSyncEnabled.v1"
        )
    }
#endif

    @Test func cloudPreferenceReopensTheSameLocalStore() {
        let localConfiguration = NagareCloud.configuration(
            schema: NagareSchema.current,
            cloudEnabled: false
        )
        let cloudConfiguration = NagareCloud.configuration(
            schema: NagareSchema.current,
            cloudEnabled: true
        )

        #expect(localConfiguration.url == cloudConfiguration.url)
    }

#if DEBUG
    @Test func developmentStoreIsNamedAndSeparateFromSwiftDataDefault() {
        #expect(NagareCloud.developmentStoreURL.lastPathComponent == "NagareDev.store")

        let localConfiguration = NagareCloud.configuration(
            schema: NagareSchema.current,
            cloudEnabled: false,
            storeURL: NagareCloud.developmentStoreURL
        )
        let cloudConfiguration = NagareCloud.configuration(
            schema: NagareSchema.current,
            cloudEnabled: true,
            storeURL: NagareCloud.developmentStoreURL
        )

        #expect(localConfiguration.url == NagareCloud.developmentStoreURL)
        #expect(cloudConfiguration.url == NagareCloud.developmentStoreURL)
    }
#endif

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
        let olderTemplate = RecurrenceTemplate(
            id: templateID,
            title: "Older template",
            notes: nil,
            rule: rule,
            currentItemID: todo.id,
            createdAt: timestamp
        )
        let newerTemplate = RecurrenceTemplate(
            id: templateID,
            title: "Newer template",
            notes: nil,
            rule: rule,
            currentItemID: todo.id,
            createdAt: timestamp
        )
        olderTemplate.modifiedAt = timestamp
        newerTemplate.modifiedAt = timestamp.addingTimeInterval(1)

        todo.project = olderProject
        todo.recurrenceTemplate = olderTemplate
        olderTemplate.project = olderProject
        newerTemplate.project = newerProject

        context.insert(olderProject)
        context.insert(newerProject)
        context.insert(olderTemplate)
        context.insert(newerTemplate)
        context.insert(todo)

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
        #expect(templates.count == 1)
        #expect(templates.first === newerTemplate)
        #expect(todo.recurrenceTemplate === newerTemplate)
        #expect(newerTemplate.project === newerProject)
    }

    @Test func recordsReceiveOneStablePhysicalIdentity() throws {
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
        #expect(assignedID == todo.id)
    }

    @Test func metadataRepairPreservesEveryRecordRevisionDate() throws {
        let context = try makeContext()
        let oldRevision = Date(timeIntervalSince1970: 100)
        let newerRevision = Date(timeIntervalSince1970: 1_000)

        let recordWithoutPhysicalID = Todo(
            title: "Migrated",
            scheduledDate: oldRevision,
            createdAt: oldRevision,
            order: "a"
        )
        recordWithoutPhysicalID.modifiedAt = oldRevision
        recordWithoutPhysicalID.syncRecordID = nil

        let unrelated = Todo(
            title: "Unrelated newer record",
            scheduledDate: newerRevision,
            createdAt: newerRevision,
            order: "b"
        )
        unrelated.modifiedAt = newerRevision
        unrelated.syncRecordID = UUID()
        context.insert(recordWithoutPhysicalID)
        context.insert(unrelated)

        let report = try SyncIntegrityRepair.repair(in: context)

        #expect(report.syncRecordIDsAssigned == 1)
        #expect(recordWithoutPhysicalID.syncRecordID == recordWithoutPhysicalID.id)
        #expect(recordWithoutPhysicalID.modifiedAt == oldRevision)
        #expect(unrelated.modifiedAt == newerRevision)
    }

    @Test func templateAndOccurrenceImportBeforeRelationshipConverge() throws {
        let context = try makeContext()
        let day = Date(timeIntervalSince1970: 1_750_000_000)
        let todo = Todo(
            title: "Imported occurrence",
            scheduledDate: day,
            createdAt: day,
            order: "i"
        )
        todo.recurrenceSequence = 0
        let template = RecurrenceTemplate(
            title: "Imported template",
            notes: nil,
            rule: try RecurrenceRule.relative(every: 1, unit: .day),
            currentItemID: todo.id,
            currentSequence: 0,
            createdAt: day
        )
        context.insert(template)
        context.insert(todo)

        let report = try SyncIntegrityRepair.repair(in: context)

        #expect(report.recurrenceLinksRepaired == 1)
        #expect(report.pendingTemplates == 0)
        #expect(todo.recurrenceTemplate === template)
    }

    @Test func templateBeforeOccurrenceImportIsAStablePendingState() throws {
        let context = try makeContext()
        let day = Date(timeIntervalSince1970: 1_750_000_000)
        let missingItemID = UUID()
        let template = RecurrenceTemplate(
            title: "Imported template",
            notes: nil,
            rule: try RecurrenceRule.relative(every: 1, unit: .day),
            currentItemID: missingItemID,
            currentSequence: 2,
            createdAt: day
        )
        context.insert(template)

        let first = try SyncReconciliationOrchestrator.reconcile(
            using: SwiftDataSyncReconciliationAdapter(context: context)
        )
        let second = try SyncReconciliationOrchestrator.reconcile(
            using: SwiftDataSyncReconciliationAdapter(context: context)
        )

        #expect(first.mutations.isEmpty)
        #expect(first.pendingTemplates == [
            SyncPendingTemplate(
                templateID: template.id,
                reason: .noSequencedOccurrences
            )
        ])
        #expect(second == first)
        #expect(
            try context.fetch(FetchDescriptor<RecurrenceTemplate>()).count
                == 1
        )
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

    @Test func timedTodoRecurrenceKeepsHistoryAndHighestActiveSequence() throws {
        let context = try makeContext()
        let day = Date(timeIntervalSince1970: 1_750_000_000)
        let first = Todo(
            title: "First",
            scheduledDate: day,
            includesTime: true,
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
            title: "Timed Todo",
            notes: nil,
            rule: rule,
            startTimeSeconds: 0,
            currentItemID: first.id,
            createdAt: day
        )
        first.recurrenceTemplate = template

        let second = Todo(
            title: "Second",
            scheduledDate: day.addingTimeInterval(86_400),
            includesTime: true,
            createdAt: day.addingTimeInterval(1),
            order: "i"
        )
        second.recurrenceSequence = 1
        second.recurrenceTemplate = template
        context.insert(template)
        context.insert(first)
        context.insert(second)

        _ = try SyncIntegrityRepair.repair(in: context)
        let todos = try context.fetch(FetchDescriptor<Todo>())

        #expect(Set(todos.map(\.id)) == [first.id, second.id])
        #expect(first.completedAt != nil)
        #expect(second.completedAt == nil)
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
            configurations: configuration
        )
        let context = ModelContext(container)
        context.autosaveEnabled = false
        return context
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
