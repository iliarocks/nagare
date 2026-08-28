import Foundation

typealias ItemID = UUID

/// An immutable view of a persisted todo used by ordering and movement logic.
nonisolated struct ItemSnapshot: Equatable, Sendable {
    let id: UUID
    let scheduledDate: Date
    let includesTime: Bool
    let endDate: Date?
    let completedAt: Date?
    let createdAt: Date
    let order: String
    let projectID: UUID?
    let projectOrder: String?

    var isCompleted: Bool { completedAt != nil }
}

nonisolated struct ProjectSnapshot: Equatable, Sendable {
    let id: UUID
    let priority: ProjectPriority
    let order: String
}

nonisolated struct ItemOrderingChange: Equatable, Sendable {
    let id: UUID
    let order: String?
    let scheduledDate: Date?
    let includesTime: Bool?
    let endDate: Date?

    init(
        id: UUID,
        order: String? = nil,
        scheduledDate: Date? = nil,
        includesTime: Bool? = nil,
        endDate: Date? = nil
    ) {
        self.id = id
        self.order = order
        self.scheduledDate = scheduledDate
        self.includesTime = includesTime
        self.endDate = endDate
    }
}

nonisolated struct ProjectOrderingChange: Equatable, Sendable {
    let id: UUID
    let order: String?
    let priority: ProjectPriority?

    init(
        id: UUID,
        order: String? = nil,
        priority: ProjectPriority? = nil
    ) {
        self.id = id
        self.order = order
        self.priority = priority
    }
}

nonisolated struct ProjectItemOrderingChange: Equatable, Sendable {
    let id: UUID
    let projectOrder: String
}
