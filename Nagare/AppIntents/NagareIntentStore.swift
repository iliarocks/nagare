import AppIntents
import CoreSpotlight
import Foundation

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
    private let orchestrator: NagareDataOrchestrator
    nonisolated(unsafe) private let searchableIndex: CSSearchableIndex

    init(orchestrator: NagareDataOrchestrator) {
        self.orchestrator = orchestrator
        self.searchableIndex = CSSearchableIndex(name: "NagareIntentContainers")
    }

    func createTodo(
        title: String,
        notes: String?,
        scheduledDate: Date,
        calendar: Calendar = .autoupdatingCurrent
    ) throws -> NagareIntentItemSnapshot {
        let result = try orchestrator.upsertItem(
            ItemDraft(
                kind: .todo,
                title: title,
                notes: notes,
                scheduledDate: calendar.startOfDay(for: scheduledDate),
                endDate: nil,
                projectID: nil,
                recurrenceRule: nil,
                eventStartTimeSeconds: nil,
                eventEndTimeSeconds: nil
            ),
            existingID: nil,
            calendar: calendar,
            at: .now
        )
        guard case .todo(let id) = result.id,
              let todo = result.snapshot.todosByID[id] else {
            throw NagareIntentStoreError.missingCreatedItem
        }
        return NagareIntentItemSnapshot(
            id: todo.id,
            title: todo.title,
            notes: todo.notes,
            scheduledDate: todo.scheduledDate,
            endDate: nil,
            createdAt: todo.createdAt
        )
    }

    func createEvent(
        title: String,
        notes: String?,
        scheduledDate: Date,
        endDate: Date?
    ) throws -> NagareIntentItemSnapshot {
        let result = try orchestrator.upsertItem(
            ItemDraft(
                kind: .event,
                title: title,
                notes: notes,
                scheduledDate: scheduledDate,
                endDate: endDate,
                projectID: nil,
                recurrenceRule: nil,
                eventStartTimeSeconds: nil,
                eventEndTimeSeconds: nil
            ),
            existingID: nil,
            calendar: .autoupdatingCurrent,
            at: .now
        )
        guard case .event(let id) = result.id,
              let event = result.snapshot.eventsByID[id] else {
            throw NagareIntentStoreError.missingCreatedItem
        }
        return NagareIntentItemSnapshot(
            id: event.id,
            title: event.title,
            notes: event.notes,
            scheduledDate: event.scheduledDate,
            endDate: event.endDate,
            createdAt: event.createdAt
        )
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

}

private enum NagareIntentStoreError: LocalizedError {
    case missingCreatedItem

    var errorDescription: String? {
        "Nagare saved the item but couldn't read it back."
    }
}
