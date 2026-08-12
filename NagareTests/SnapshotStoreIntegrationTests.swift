import Foundation
import SwiftData
import Testing
@testable import Nagare

@MainActor
struct SnapshotStoreIntegrationTests {
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

    @Test func historyEventRebuildsPublishedSnapshot() async throws {
        let storeURL = temporaryStoreURL()
        defer { removeStoreFiles(at: storeURL) }

        let readerContainer = try makeContainer(at: storeURL)
        let seedContext = ModelContext(readerContainer)
        seedContext.insert(Todo(title: "Original", order: "a"))
        try seedContext.save()

        let store = try makeStore(in: readerContainer)
        let monitor = try SyncIntegrityMonitor(
            modelContainer: readerContainer,
            onReconciled: { try? store.reload() }
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
        let monitor = try SyncIntegrityMonitor(
            modelContainer: readerContainer,
            onReconciled: { try? store.reload() }
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
        let monitor = try SyncIntegrityMonitor(
            modelContainer: readerContainer,
            onReconciled: { try? store.reload() }
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
                kind: .todo,
                title: "Created",
                notes: nil,
                scheduledDate: createdAt,
                endDate: nil,
                projectID: nil,
                recurrenceRule: nil,
                eventStartTimeSeconds: nil,
                eventEndTimeSeconds: nil
            ),
            existingID: nil,
            at: createdAt
        )
        guard case .todo(let todoID) = id else {
            Issue.record("Expected a Todo identity")
            return
        }
        #expect(store.snapshot.todosByID[todoID]?.modifiedAt == createdAt)

        try store.updateNote(
            .todo(todoID),
            title: "Updated",
            notes: nil,
            at: updatedAt
        )
        #expect(store.snapshot.todosByID[todoID]?.modifiedAt == updatedAt)
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
            [.todo(second.id)],
            before: .todo(first.id),
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
            migrationPlan: NagareMigrationPlan.self,
            configurations: configuration
        )
    }

    private func makeStore(in container: ModelContainer) throws -> NagareDataStore {
        let repository = SwiftDataNagareRepository(modelContainer: container)
        return try NagareDataStore(
            orchestrator: NagareDataOrchestrator(
                reader: repository,
                writer: repository
            ),
            calendarImportOrchestrator: CalendarImportOrchestrator(
                reader: repository,
                writer: repository,
                inbox: PendingCalendarImportAdapter()
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
