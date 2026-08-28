import AppIntents
import CoreSpotlight
import Foundation

struct NagareIntentItemSnapshot: Sendable {
    let id: UUID
    let title: String
    let notes: String?
    let scheduledDate: Date
    let includesTime: Bool
    let endDate: Date?
    let createdAt: Date
}

/// The complete Siri-facing I/O surface. It deliberately supports creation
/// only; querying, updating, deleting, completing, and recurrence transitions
/// remain app-only operations.
@MainActor
final class NagareIntentStore: @unchecked Sendable {
    private var orchestrator: NagareDataOrchestrator?
    nonisolated(unsafe) private let searchableIndex: CSSearchableIndex

    init(orchestrator: NagareDataOrchestrator? = nil) {
        self.orchestrator = orchestrator
        self.searchableIndex = CSSearchableIndex(name: "NagareIntentContainers")
    }

    func connect(to orchestrator: NagareDataOrchestrator) {
        self.orchestrator = orchestrator
    }

    func disconnect() {
        orchestrator = nil
    }

    func createTodo(
        title: String,
        notes: String?,
        scheduledDate: Date,
        includesTime: Bool = false,
        calendar: Calendar = .autoupdatingCurrent
    ) throws -> NagareIntentItemSnapshot {
        guard let orchestrator else {
            throw NagareIntentStoreError.temporarilyUnavailable
        }
        let result = try orchestrator.upsertItem(
            ItemDraft(
                title: title,
                notes: notes,
                scheduledDate: includesTime
                    ? scheduledDate
                    : calendar.startOfDay(for: scheduledDate),
                includesTime: includesTime,
                endDate: nil,
                projectID: nil,
                recurrenceRule: nil,
                startTimeSeconds: nil,
                endTimeSeconds: nil
            ),
            existingID: nil,
            calendar: calendar,
            at: .now
        )
        guard let todo = result.snapshot.todosByID[result.id] else {
            throw NagareIntentStoreError.missingCreatedItem
        }
        return NagareIntentItemSnapshot(
            id: todo.id,
            title: todo.title,
            notes: todo.notes,
            scheduledDate: todo.scheduledDate,
            includesTime: todo.includesTime,
            endDate: nil,
            createdAt: todo.createdAt
        )
    }

    func createTimedTodo(
        title: String,
        notes: String?,
        scheduledDate: Date,
        endDate: Date?
    ) throws -> NagareIntentItemSnapshot {
        guard let orchestrator else {
            throw NagareIntentStoreError.temporarilyUnavailable
        }
        let result = try orchestrator.upsertItem(
            ItemDraft(
                title: title,
                notes: notes,
                scheduledDate: scheduledDate,
                includesTime: true,
                endDate: endDate,
                projectID: nil,
                recurrenceRule: nil,
                startTimeSeconds: nil,
                endTimeSeconds: nil
            ),
            existingID: nil,
            calendar: .autoupdatingCurrent,
            at: .now
        )
        guard let todo = result.snapshot.todosByID[result.id] else {
            throw NagareIntentStoreError.missingCreatedItem
        }
        return NagareIntentItemSnapshot(
            id: todo.id,
            title: todo.title,
            notes: todo.notes,
            scheduledDate: todo.scheduledDate,
            includesTime: todo.includesTime,
            endDate: todo.endDate,
            createdAt: todo.createdAt
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
    case temporarilyUnavailable

    var errorDescription: String? {
        switch self {
        case .missingCreatedItem:
            "Nagare saved the item but couldn't read it back."
        case .temporarilyUnavailable:
            "Nagare is updating its data connection. Try again in a moment."
        }
    }
}
