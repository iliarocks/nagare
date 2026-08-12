import Foundation

/// Coordinates the non-atomic edge between the shared extension inbox and
/// SwiftData. Database upsert happens first; acknowledgement happens second.
/// Retrying after an acknowledgement failure is safe because source IDs are
/// idempotent.
@MainActor
final class CalendarImportOrchestrator {
    private let reader: any NagareDataReading
    private let writer: any NagareDataWriting
    private let inbox: any CalendarImportInbox

    init(
        reader: any NagareDataReading,
        writer: any NagareDataWriting,
        inbox: any CalendarImportInbox
    ) {
        self.reader = reader
        self.writer = writer
        self.inbox = inbox
    }

    func importPending(
        at date: Date
    ) throws -> (events: [EventRecordSnapshot], snapshot: NagareDataSnapshot) {
        var importedIDs: [UUID] = []
        for pending in try inbox.load() {
            let snapshot = try reader.load()
            let plan = try NagareCommandPlanner.upsertCalendarEvent(
                pending.draft,
                in: snapshot
            )
            let id = try writer.upsertCalendarEvent(
                plan,
                at: date
            )
            try inbox.remove(token: pending.token)
            importedIDs.append(id)
        }

        let snapshot = try reader.load()
        let eventsByID = snapshot.eventsByID
        return (
            importedIDs.compactMap { eventsByID[$0] },
            snapshot
        )
    }
}
