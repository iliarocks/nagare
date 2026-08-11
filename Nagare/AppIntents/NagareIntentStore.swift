import AppIntents
import CoreSpotlight
import Foundation
import SwiftData

struct NagareIntentItemSnapshot: Sendable {
    let id: UUID
    let title: String
    let notes: String?
    let scheduledDate: Date
    let endDate: Date?
    let createdAt: Date
}

/// The complete Siri-facing I/O surface. It deliberately supports creation
/// only; querying, updating, deleting, completing, and recurrence transitions
/// remain app-only operations.
@MainActor
final class NagareIntentStore: @unchecked Sendable {
    let modelContainer: ModelContainer
    private let modelContext: ModelContext
    nonisolated(unsafe) private let searchableIndex: CSSearchableIndex

    init(modelContainer: ModelContainer) {
        self.modelContainer = modelContainer
        self.modelContext = modelContainer.mainContext
        self.searchableIndex = CSSearchableIndex(name: "NagareIntentContainers")
    }

    func createTodo(
        title: String,
        notes: String?,
        scheduledDate: Date,
        calendar: Calendar = .autoupdatingCurrent
    ) throws -> NagareIntentItemSnapshot {
        let order = try ItemOrdering.nextOrder(in: modelContext)
        let todo = Todo(
            title: title,
            notes: notes,
            scheduledDate: scheduledDate,
            order: order,
            calendar: calendar
        )
        modelContext.insert(todo)
        try SwiftDataTransaction.save(modelContext)
        return snapshot(todo)
    }

    func createEvent(
        title: String,
        notes: String?,
        scheduledDate: Date,
        endDate: Date?
    ) throws -> NagareIntentItemSnapshot {
        let order = try ItemOrdering.nextOrder(in: modelContext)
        let event = Event(
            title: title,
            notes: notes,
            scheduledDate: scheduledDate,
            endDate: endDate,
            order: order
        )
        modelContext.insert(event)
        try SwiftDataTransaction.save(modelContext)
        return snapshot(event)
    }

    /// The static Nagare list and calendar are the only indexed entities Siri
    /// needs in order to resolve the two create schemas.
    func refreshIntentContainerIndex() async throws {
        try await searchableIndex.deleteAllSearchableItems()
        try await searchableIndex.indexAppEntities([
            NagareReminderListEntity.nagare
        ])
        try await searchableIndex.indexAppEntities([
            NagareCalendarEntity.nagare
        ])
    }

    private func snapshot(_ todo: Todo) -> NagareIntentItemSnapshot {
        NagareIntentItemSnapshot(
            id: todo.id,
            title: todo.title,
            notes: todo.notes,
            scheduledDate: todo.scheduledDate,
            endDate: nil,
            createdAt: todo.createdAt
        )
    }

    private func snapshot(_ event: Event) -> NagareIntentItemSnapshot {
        NagareIntentItemSnapshot(
            id: event.id,
            title: event.title,
            notes: event.notes,
            scheduledDate: event.scheduledDate,
            endDate: event.endDate,
            createdAt: event.createdAt
        )
    }
}
