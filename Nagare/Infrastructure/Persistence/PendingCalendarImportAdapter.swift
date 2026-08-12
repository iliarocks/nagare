import Foundation

/// File-backed adapter for the share extension's calendar inbox. Tokens are
/// opaque outside this boundary; resolved URLs never enter application logic.
@MainActor
final class PendingCalendarImportAdapter: CalendarImportInbox {
    private var importsByToken: [String: PendingCalendarImport] = [:]

    func load() throws -> [PendingCalendarEvent] {
        let pending = try PendingCalendarImportStore.pendingImports()
        importsByToken = Dictionary(
            uniqueKeysWithValues: pending.map {
                ($0.fileURL.lastPathComponent, $0)
            }
        )
        return pending.map {
            PendingCalendarEvent(
                token: $0.fileURL.lastPathComponent,
                draft: $0.draft
            )
        }
    }

    func remove(token: String) throws {
        guard let pending = importsByToken.removeValue(forKey: token) else {
            throw PendingCalendarImportAdapterError.unknownToken
        }
        try PendingCalendarImportStore.remove(pending)
    }
}

private enum PendingCalendarImportAdapterError: LocalizedError {
    case unknownToken

    var errorDescription: String? {
        "Nagare couldn't acknowledge an unknown calendar inbox entry."
    }
}
