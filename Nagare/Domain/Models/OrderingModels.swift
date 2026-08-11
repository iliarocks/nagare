import Foundation

nonisolated enum ItemID: Hashable, Sendable {
    case todo(UUID)
    case event(UUID)

    var description: String {
        switch self {
        case .todo(let id):
            "todo-\(id)"
        case .event(let id):
            "event-\(id)"
        }
    }
}

/// An immutable view of a persisted item used by domain logic.
///
/// SwiftData records are deliberately not exposed here. A snapshot can be
/// freely compared, tested, and passed between layers without allowing domain
/// code to mutate the store by accident.
nonisolated struct ItemSnapshot: Equatable, Sendable {
    enum Kind: Equatable, Sendable {
        case todo
        case event
    }

    let id: ItemID
    let kind: Kind
    let scheduledDate: Date
    let endDate: Date?
    let completedAt: Date?
    let createdAt: Date
    let order: String
    let projectID: UUID?
    let projectOrder: String?

    var isCompleted: Bool {
        completedAt != nil
    }
}

/// An immutable view of a persisted project used by domain logic.
nonisolated struct ProjectSnapshot: Equatable, Sendable {
    let id: UUID
    let isPriority: Bool
    let order: String
}

/// The smallest possible write instruction produced by ordering logic.
nonisolated struct ItemOrderingChange: Equatable, Sendable {
    let id: ItemID
    let order: String?
    let scheduledDate: Date?
    let endDate: Date?

    init(
        id: ItemID,
        order: String? = nil,
        scheduledDate: Date? = nil,
        endDate: Date? = nil
    ) {
        self.id = id
        self.order = order
        self.scheduledDate = scheduledDate
        self.endDate = endDate
    }
}

nonisolated struct ProjectOrderingChange: Equatable, Sendable {
    let id: UUID
    let order: String?
    let isPriority: Bool?

    init(
        id: UUID,
        order: String? = nil,
        isPriority: Bool? = nil
    ) {
        self.id = id
        self.order = order
        self.isPriority = isPriority
    }
}

nonisolated struct ProjectItemOrderingChange: Equatable, Sendable {
    let id: ItemID
    let projectOrder: String
}
