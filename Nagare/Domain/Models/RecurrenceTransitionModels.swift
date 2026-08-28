import Foundation

nonisolated struct RecurrenceTransitionTemplate: Equatable, Sendable {
    let title: String
    let notes: String?
    let rule: RecurrenceRule
    let startTimeSeconds: Int?
    let endTimeSeconds: Int?
    let currentSequence: Int
}

nonisolated struct RecurrenceOccurrenceSnapshot: Equatable, Sendable {
    let scheduledDate: Date
    let order: String
    let projectOrder: String?
}

nonisolated struct TodoOccurrenceDraft: Equatable, Sendable {
    let title: String
    let notes: String?
    let scheduledDate: Date
    let includesTime: Bool
    let endDate: Date?
    let createdAt: Date
    let order: String
    let projectOrder: String?
    let sequence: Int
}
