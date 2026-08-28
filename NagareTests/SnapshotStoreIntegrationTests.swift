import Foundation
import Observation
import SwiftData
import Testing
@testable import Nagare

@MainActor
struct SnapshotStoreIntegrationTests {
    @Test func foregroundActivationRecoversHistoryObservation() throws {
        let storeURL = temporaryStoreURL()
        defer { removeStoreFiles(at: storeURL) }

        let container = try makeContainer(at: storeURL)
        let observer = TestSyncHistoryObserver()
        var attempts = 0
        let monitor = SyncIntegrityMonitor(
            modelContainer: container,
            requiresReconciliation: false,
            historyObserverFactory: { _ in
                attempts += 1
                if attempts == 1 {
                    throw TestHistoryObserverError.unavailable
                }
                return observer
            }
        )

        #expect(!monitor.isObservingHistory)
        monitor.applicationDidBecomeActive()
        #expect(monitor.isObservingHistory)
        #expect(attempts == 2)
    }

    @Test func freshReadSeesUpdateFromAnotherStoreCoordinator() throws {
        let storeURL = temporaryStoreURL()
        defer { removeStoreFiles(at: storeURL) }

        let readerContainer = try makeContainer(at: storeURL)
        let seedContext = ModelContext(readerContainer)
        seedContext.insert(Todo(title: "Original", order: "a"))
        try seedContext.save()

        let repository = SwiftDataNagareRepository(
            modelContainer: readerContainer
        )
        #expect(try repository.load().todos.map(\.title) == ["Original"])

        let writerContainer = try makeContainer(at: storeURL)
        let writerContext = ModelContext(writerContainer)
        let writerTodo = try #require(
            try writerContext.fetch(FetchDescriptor<Todo>()).first
        )
        writerTodo.title = "External update"
        try writerContext.save()

        #expect(
            try repository.load().todos.map(\.title) == ["External update"]
        )
    }

    @Test func onDiskMutationsResolveConcreteSwiftDataModels() throws {
        let storeURL = temporaryStoreURL()
        defer { removeStoreFiles(at: storeURL) }

        let container = try makeContainer(at: storeURL)
        let context = ModelContext(container)
        let transactionDate = Date(timeIntervalSinceReferenceDate: 800_000_000)
        let project = Project(title: "Project", order: "a")
        let todo = Todo(
            title: "Todo",
            scheduledDate: transactionDate,
            order: "a"
        )
        let timedTodo = Todo(
            title: "Timed Todo",
            scheduledDate: transactionDate,
            includesTime: true,
            order: "b"
        )
        let template = RecurrenceTemplate(
            title: "Template",
            notes: nil,
            rule: try .relative(every: 1, unit: .day),
            currentItemID: todo.id
        )
        context.insert(project)
        context.insert(todo)
        context.insert(timedTodo)
        context.insert(template)
        try context.save()

        let repository = SwiftDataNagareRepository(modelContainer: container)
        try repository.updateNote(
            .todo(todo.id),
            title: "Edited Todo",
            notes: "Todo notes",
            at: transactionDate
        )
        try repository.updateNote(
            .todo(timedTodo.id),
            title: "Edited Timed Todo",
            notes: "Timed Todo notes",
            at: transactionDate
        )
        try repository.updateNote(
            .recurrenceTemplate(template.id),
            title: "Edited Template",
            notes: "Template notes",
            at: transactionDate
        )
        try repository.updateProject(
            project.id,
            title: "Edited Project",
            notes: "Project notes",
            at: transactionDate
        )
        try repository.saveItemOrdering(
            [
                ItemOrderingChange(id: todo.id, order: "c"),
                ItemOrderingChange(id: timedTodo.id, order: "d")
            ],
            at: transactionDate
        )
        try repository.saveProjectOrdering(
            [
                ProjectOrderingChange(
                    id: project.id,
                    order: "e",
                    priority: .high
                )
            ],
            at: transactionDate
        )

        let snapshot = try repository.load()
        #expect(snapshot.todosByID[todo.id]?.title == "Edited Todo")
        #expect(snapshot.todosByID[todo.id]?.notes == "Todo notes")
        #expect(snapshot.todosByID[todo.id]?.order == "c")
        #expect(
            snapshot.todosByID[timedTodo.id]?.title == "Edited Timed Todo"
        )
        #expect(
            snapshot.todosByID[timedTodo.id]?.notes == "Timed Todo notes"
        )
        #expect(snapshot.todosByID[timedTodo.id]?.order == "d")
        #expect(
            snapshot.templatesByID[template.id]?.title == "Edited Template"
        )
        #expect(
            snapshot.templatesByID[template.id]?.notes == "Template notes"
        )
        #expect(snapshot.projectsByID[project.id]?.title == "Edited Project")
        #expect(snapshot.projectsByID[project.id]?.notes == "Project notes")
        #expect(snapshot.projectsByID[project.id]?.order == "e")
        #expect(snapshot.projectsByID[project.id]?.isPriority == true)
    }

    @Test func historyEventRebuildsPublishedSnapshot() async throws {
        let storeURL = temporaryStoreURL()
        defer { removeStoreFiles(at: storeURL) }

        let readerContainer = try makeContainer(at: storeURL)
        let seedContext = ModelContext(readerContainer)
        seedContext.insert(Todo(title: "Original", order: "a"))
        try seedContext.save()

        let store = try makeStore(in: readerContainer)
        let monitor = SyncIntegrityMonitor(
            modelContainer: readerContainer,
            onPersistedChange: { _ = try? store.reload() }
        )
        _ = monitor
        #expect(store.todos.map(\.title) == ["Original"])

        let writerContainer = try makeContainer(at: storeURL)
        let writerContext = ModelContext(writerContainer)
        let writerTodo = try #require(
            try writerContext.fetch(FetchDescriptor<Todo>()).first
        )
        writerTodo.title = "External update"
        try writerContext.save()

        try await waitUntil {
            store.todos.map(\.title) == ["External update"]
        }
    }

    @Test func historyEventPublishesExternalReorder() async throws {
        let storeURL = temporaryStoreURL()
        defer { removeStoreFiles(at: storeURL) }

        let readerContainer = try makeContainer(at: storeURL)
        let seedContext = ModelContext(readerContainer)
        let first = Todo(title: "First", order: "a")
        let second = Todo(title: "Second", order: "b")
        seedContext.insert(first)
        seedContext.insert(second)
        try seedContext.save()

        let store = try makeStore(in: readerContainer)
        let monitor = SyncIntegrityMonitor(
            modelContainer: readerContainer,
            onPersistedChange: { _ = try? store.reload() }
        )
        _ = monitor

        let writerContainer = try makeContainer(at: storeURL)
        let writerContext = ModelContext(writerContainer)
        let writerTodos = try writerContext.fetch(FetchDescriptor<Todo>())
        let writerFirst = try #require(
            writerTodos.first { $0.id == first.id }
        )
        let writerSecond = try #require(
            writerTodos.first { $0.id == second.id }
        )
        writerFirst.order = "b"
        writerSecond.order = "a"
        try writerContext.save()

        try await waitUntil {
            store.todos.sorted { $0.order < $1.order }.map(\.id)
                == [second.id, first.id]
        }
    }

    @Test func successiveHistoryEventsKeepReplacingPublishedState() async throws {
        let storeURL = temporaryStoreURL()
        defer { removeStoreFiles(at: storeURL) }

        let readerContainer = try makeContainer(at: storeURL)
        let seedContext = ModelContext(readerContainer)
        let first = Todo(title: "First", order: "a")
        let second = Todo(title: "Second", order: "b")
        seedContext.insert(first)
        seedContext.insert(second)
        try seedContext.save()

        let store = try makeStore(in: readerContainer)
        let monitor = SyncIntegrityMonitor(
            modelContainer: readerContainer,
            onPersistedChange: { _ = try? store.reload() }
        )
        _ = monitor

        let writerContainer = try makeContainer(at: storeURL)
        let writerContext = ModelContext(writerContainer)
        let writerTodos = try writerContext.fetch(FetchDescriptor<Todo>())
        let writerFirst = try #require(
            writerTodos.first { $0.id == first.id }
        )
        let writerSecond = try #require(
            writerTodos.first { $0.id == second.id }
        )

        writerFirst.title = "First edit"
        try writerContext.save()
        try await waitUntil {
            store.snapshot.todosByID[first.id]?.title == "First edit"
        }

        writerFirst.title = "Second edit"
        try writerContext.save()
        try await waitUntil {
            store.snapshot.todosByID[first.id]?.title == "Second edit"
        }

        writerFirst.order = "b"
        writerSecond.order = "a"
        try writerContext.save()
        try await waitUntil {
            store.todos.sorted { $0.order < $1.order }.map(\.id)
                == [second.id, first.id]
        }
    }

    @Test func commandPublishesFreshValueWithoutRefreshingOldObject() throws {
        let configuration = ModelConfiguration(
            isStoredInMemoryOnly: true,
            cloudKitDatabase: .none
        )
        let container = try ModelContainer(
            for: Project.self,
            Todo.self,
            Event.self,
            RecurrenceTemplate.self,
            configurations: configuration
        )
        let oldContext = ModelContext(container)
        let oldObject = Todo(title: "Old", order: "a")
        oldContext.insert(oldObject)
        try oldContext.save()

        let store = try makeStore(in: container)
        try store.updateNote(
            .todo(oldObject.id),
            title: "New",
            notes: nil
        )

        #expect(oldObject.title == "Old")
        #expect(store.todos.map(\.title) == ["New"])
    }

    @Test func commandBoundaryUsesTheExplicitTransactionDate() throws {
        let configuration = ModelConfiguration(
            isStoredInMemoryOnly: true,
            cloudKitDatabase: .none
        )
        let container = try ModelContainer(
            for: Project.self,
            Todo.self,
            Event.self,
            RecurrenceTemplate.self,
            configurations: configuration
        )
        let store = try makeStore(in: container)
        let createdAt = Date(timeIntervalSinceReferenceDate: 800_000_000)
        let updatedAt = createdAt.addingTimeInterval(60)

        let id = try store.upsertItem(
            ItemDraft(
                title: "Created",
                notes: nil,
                scheduledDate: createdAt,
                includesTime: false,
                endDate: nil,
                projectID: nil,
                recurrenceRule: nil,
                startTimeSeconds: nil,
                endTimeSeconds: nil
            ),
            existingID: nil,
            at: createdAt
        )
        let todoID = id
        #expect(store.snapshot.todosByID[todoID]?.modifiedAt == createdAt)

        try store.updateNote(
            .todo(todoID),
            title: "Updated",
            notes: nil,
            at: updatedAt
        )
        #expect(store.snapshot.todosByID[todoID]?.modifiedAt == updatedAt)
    }

    @Test
    func changingCurrentOccurrenceScheduleKeepsTemplateTimesAndRebasesProjection()
        throws
    {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        func date(
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

        let configuration = ModelConfiguration(
            isStoredInMemoryOnly: true,
            cloudKitDatabase: .none
        )
        let container = try ModelContainer(
            for: Project.self,
            Todo.self,
            Event.self,
            RecurrenceTemplate.self,
            configurations: configuration
        )
        let context = ModelContext(container)
        let current = Todo(
            title: "Daily timed occurrence",
            scheduledDate: date(2026, 7, 1, hour: 9, minute: 30),
            includesTime: true,
            endDate: date(2026, 7, 1, hour: 10, minute: 30),
            order: "a",
            calendar: calendar
        )
        context.insert(current)
        let template = try RecurrencePersistence.createTemplate(
            for: current,
            rule: try .relative(every: 1, unit: .day),
            in: context,
            calendar: calendar
        )
        let templateID = template.id
        let store = try makeStore(in: container)

        let before = RecurrenceProjectionLogic.generate(
            from: store.snapshot.recurrenceProjectionInput,
            starting: date(2026, 7, 2),
            through: date(2026, 7, 6),
            calendar: calendar
        )
        #expect(before.items.first?.date == date(2026, 7, 2))
        #expect(
            before.items.first?.startDate
                == date(2026, 7, 2, hour: 9, minute: 30)
        )

        try store.updateTodoSchedule(
            current.id,
            scheduledDate: date(2026, 7, 1, hour: 14, minute: 15),
            includesTime: true,
            endDate: date(2026, 7, 1, hour: 15, minute: 15),
            calendar: calendar
        )

        let timeEditedCurrent = try #require(
            store.snapshot.todosByID[current.id]
        )
        let unchangedTemplate = try #require(
            store.snapshot.templatesByID[templateID]
        )
        #expect(
            timeEditedCurrent.scheduledDate
                == date(2026, 7, 1, hour: 14, minute: 15)
        )
        #expect(
            timeEditedCurrent.endDate
                == date(2026, 7, 1, hour: 15, minute: 15)
        )
        #expect(unchangedTemplate.startTimeSeconds == 9 * 3_600 + 30 * 60)
        #expect(unchangedTemplate.endTimeSeconds == 10 * 3_600 + 30 * 60)

        let afterTimeEdit = RecurrenceProjectionLogic.generate(
            from: store.snapshot.recurrenceProjectionInput,
            starting: date(2026, 7, 2),
            through: date(2026, 7, 6),
            calendar: calendar
        )
        #expect(afterTimeEdit.items.first?.date == date(2026, 7, 2))
        #expect(
            afterTimeEdit.items.first?.startDate
                == date(2026, 7, 2, hour: 9, minute: 30)
        )

        try store.updateTodoSchedule(
            current.id,
            scheduledDate: date(2026, 7, 3, hour: 14, minute: 15),
            includesTime: true,
            endDate: date(2026, 7, 3, hour: 15, minute: 15),
            calendar: calendar
        )

        let afterDateEdit = RecurrenceProjectionLogic.generate(
            from: store.snapshot.recurrenceProjectionInput,
            starting: date(2026, 7, 2),
            through: date(2026, 7, 6),
            calendar: calendar
        )
        #expect(afterDateEdit.items.first?.date == date(2026, 7, 4))
        #expect(
            afterDateEdit.items.first?.startDate
                == date(2026, 7, 4, hour: 9, minute: 30)
        )
        #expect(
            afterDateEdit.items.first?.endDate
                == date(2026, 7, 4, hour: 10, minute: 30)
        )
    }

    @Test func projectReorderRepairsMissingLegacyOrderInSameTransaction() throws {
        let configuration = ModelConfiguration(
            isStoredInMemoryOnly: true,
            cloudKitDatabase: .none
        )
        let container = try ModelContainer(
            for: Project.self,
            Todo.self,
            Event.self,
            RecurrenceTemplate.self,
            configurations: configuration
        )
        let context = ModelContext(container)
        let project = Project(title: "Project", order: "a")
        let first = Todo(title: "First", order: "a")
        let second = Todo(title: "Second", order: "b")
        first.project = project
        second.project = project
        first.projectOrder = nil
        second.projectOrder = "invalid!"
        context.insert(project)
        context.insert(first)
        context.insert(second)
        try context.save()

        let store = try makeStore(in: container)
        try store.moveProjectItems(
            [second.id],
            before: first.id,
            projectID: project.id
        )

        let ordered = store.snapshot.todos
            .filter { $0.projectID == project.id }
            .sorted { ($0.projectOrder ?? "") < ($1.projectOrder ?? "") }
        #expect(ordered.map(\.id) == [second.id, first.id])
        #expect(ordered.allSatisfy {
            $0.projectOrder.map(FractionalIndex.isValid) == true
        })
    }

    private func waitUntil(
        _ condition: () -> Bool
    ) async throws {
        for _ in 0..<120 {
            if condition() { return }
            try await Task.sleep(for: .milliseconds(50))
        }
        Issue.record("History did not rebuild the immutable snapshot")
    }

    private func temporaryStoreURL() -> URL {
        FileManager.default.temporaryDirectory.appending(
            path: "NagareSnapshot-\(UUID().uuidString).store"
        )
    }

    private func makeContainer(at url: URL) throws -> ModelContainer {
        let configuration = ModelConfiguration(
            "SnapshotStore",
            schema: NagareSchema.current,
            url: url,
            cloudKitDatabase: .none
        )
        return try ModelContainer(
            for: NagareSchema.current,
            configurations: configuration
        )
    }

    private func makeStore(in container: ModelContainer) throws -> NagareDataStore {
        let repository = SwiftDataNagareRepository(modelContainer: container)
        return try NagareDataStore(
            orchestrator: NagareDataOrchestrator(
                reader: repository,
                writer: repository
            )
        )
    }

    private func removeStoreFiles(at url: URL) {
        for suffix in ["", "-wal", "-shm"] {
            try? FileManager.default.removeItem(
                at: URL(filePath: url.path + suffix)
            )
        }
    }
}

@MainActor
@Observable
private final class TestSyncHistoryObserver: SyncHistoryObserving {
    var eventCounter = 0
}

private enum TestHistoryObserverError: Error {
    case unavailable
}
