import Foundation

nonisolated enum RecurrenceItemType: String, Codable, Sendable {
    case todo
    case event
}

nonisolated struct RecurrenceProjectionTemplateSnapshot: Equatable, Sendable {
    let metadata: SyncRecordMetadata
    let itemTypeRawValue: String
    let modeRawValue: String
    let unitRawValue: String
    let interval: Int
    let anchors: [Int]
    let reference: Date?
    let startTimeSeconds: Int?
    let endTimeSeconds: Int?
    let currentItemID: UUID
    let currentSequence: Int
}

nonisolated struct RecurrenceProjectionOccurrenceSnapshot:
    Equatable,
    Sendable
{
    let metadata: SyncRecordMetadata
    let itemType: RecurrenceItemType
    let scheduledDate: Date
    let completedAt: Date?
    let order: String
    let recurrenceSequence: Int?
    let recurrenceTemplateID: UUID?
}

nonisolated struct RecurrenceProjectionInput: Equatable, Sendable {
    let templates: [RecurrenceProjectionTemplateSnapshot]
    let occurrences: [RecurrenceProjectionOccurrenceSnapshot]
}

nonisolated struct ProjectedRecurrenceItem: Equatable, Sendable {
    let templateReference: SyncRecordReference
    let templateID: UUID
    let date: Date
    let startDate: Date?
    let endDate: Date?
    let itemType: RecurrenceItemType
    let order: String
}

nonisolated enum RecurrenceProjectionIssueKind: Equatable, Sendable {
    case pendingCurrentOccurrence(id: UUID, sequence: Int)
    case unknownItemType(String)
    case invalidRule(String)
    case missingEventStartTime
    case invalidEventTime(Int)
    case dateCalculationFailed
}

nonisolated struct RecurrenceProjectionIssue: Equatable, Sendable {
    let templateID: UUID
    let kind: RecurrenceProjectionIssueKind

    var isPendingImport: Bool {
        if case .pendingCurrentOccurrence = kind {
            return true
        }
        return false
    }
}

nonisolated struct RecurrenceProjectionResult: Equatable, Sendable {
    let items: [ProjectedRecurrenceItem]
    let issues: [RecurrenceProjectionIssue]
}
