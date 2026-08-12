import Foundation
import SwiftData
import Testing
@testable import Nagare

@MainActor
struct CalendarImportOrchestratorTests {
    @Test func importsThenAcknowledgesTheInboxEntry() throws {
        let repository = try makeRepository()
        let inbox = TestCalendarInbox(pending: [pendingEvent()])
        let orchestrator = CalendarImportOrchestrator(
            reader: repository,
            writer: repository,
            inbox: inbox
        )

        let result = try orchestrator.importPending(at: transactionDate)

        #expect(result.events.map(\.title) == ["Planning"])
        #expect(result.snapshot.events.count == 1)
        #expect(inbox.removedTokens == ["invite.json"])
    }

    @Test func acknowledgementFailureRetriesWithoutDuplicatingTheEvent() throws {
        let repository = try makeRepository()
        let inbox = TestCalendarInbox(
            pending: [pendingEvent()],
            failsRemoval: true
        )
        let orchestrator = CalendarImportOrchestrator(
            reader: repository,
            writer: repository,
            inbox: inbox
        )

        #expect(throws: TestCalendarInbox.InboxError.self) {
            _ = try orchestrator.importPending(at: transactionDate)
        }
        #expect(try repository.load().events.count == 1)

        inbox.failsRemoval = false
        _ = try orchestrator.importPending(
            at: transactionDate.addingTimeInterval(1)
        )

        #expect(try repository.load().events.count == 1)
        #expect(inbox.removedTokens == ["invite.json"])
    }

    private var transactionDate: Date {
        Date(timeIntervalSinceReferenceDate: 800_000_000)
    }

    private func pendingEvent() -> PendingCalendarEvent {
        PendingCalendarEvent(
            token: "invite.json",
            draft: ICalendarEventDraft(
                sourceIdentifier: "planning@example.com",
                title: "Planning",
                notes: nil,
                scheduledDate: transactionDate,
                endDate: transactionDate.addingTimeInterval(3_600),
                isAllDay: false
            )
        )
    }

    private func makeRepository() throws -> SwiftDataNagareRepository {
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
        return SwiftDataNagareRepository(modelContainer: container)
    }
}

@MainActor
private final class TestCalendarInbox: CalendarImportInbox {
    enum InboxError: Error {
        case removalFailed
    }

    private let pending: [PendingCalendarEvent]
    var failsRemoval: Bool
    private(set) var removedTokens: [String] = []

    init(
        pending: [PendingCalendarEvent],
        failsRemoval: Bool = false
    ) {
        self.pending = pending
        self.failsRemoval = failsRemoval
    }

    func load() throws -> [PendingCalendarEvent] {
        pending.filter { !removedTokens.contains($0.token) }
    }

    func remove(token: String) throws {
        if failsRemoval { throw InboxError.removalFailed }
        removedTokens.append(token)
    }
}
