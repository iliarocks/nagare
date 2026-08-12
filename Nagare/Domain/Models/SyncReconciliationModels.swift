import Foundation

nonisolated enum SyncEntityKind: String, CaseIterable, Sendable {
    case project
    case recurrenceTemplate
    case todo
    case event
}

/// Store-local token used only to address an explicit adapter operation. It is
/// never consulted when deciding which replicated value wins a conflict.
nonisolated struct SyncRecordReference: Hashable, Sendable {
    let kind: SyncEntityKind
    let localID: String
}

/// Immutable replicated identity and revision metadata. Legacy V1 records do
/// not have a physical ID; their semantic UUID is the deterministic upgrade
/// value, avoiding a different random repair on every device.
nonisolated struct SyncRecordMetadata: Hashable, Sendable {
    let reference: SyncRecordReference
    let semanticID: UUID
    let physicalID: UUID?
    let createdAt: Date
    let modifiedAt: Date?
    let stableTieBreaker: [String]

    var resolvedPhysicalID: UUID {
        physicalID ?? semanticID
    }

    var revisionDate: Date {
        modifiedAt ?? createdAt
    }
}

nonisolated struct SyncProjectSnapshot: Equatable, Sendable {
    let metadata: SyncRecordMetadata
}

nonisolated struct SyncRecurrenceTemplateSnapshot: Equatable, Sendable {
    let metadata: SyncRecordMetadata
    let itemTypeRawValue: String
    let currentItemID: UUID
    let currentSequence: Int
    let projectID: UUID?
}

nonisolated struct SyncTodoSnapshot: Equatable, Sendable {
    let metadata: SyncRecordMetadata
    let completedAt: Date?
    let recurrenceSequence: Int?
    let recurrenceTemplateID: UUID?
    let projectID: UUID?
}

nonisolated struct SyncEventSnapshot: Equatable, Sendable {
    let metadata: SyncRecordMetadata
    let calendarIdentifier: String?
    let recurrenceSequence: Int?
    let recurrenceTemplateID: UUID?
    let projectID: UUID?
}

nonisolated struct SyncGraphSnapshot: Equatable, Sendable {
    let projects: [SyncProjectSnapshot]
    let recurrenceTemplates: [SyncRecurrenceTemplateSnapshot]
    let todos: [SyncTodoSnapshot]
    let events: [SyncEventSnapshot]

    var allMetadata: [SyncRecordMetadata] {
        projects.map(\.metadata)
            + recurrenceTemplates.map(\.metadata)
            + todos.map(\.metadata)
            + events.map(\.metadata)
    }
}

nonisolated enum SyncPendingReason: Equatable, Sendable {
    case noSequencedOccurrences
    case waitingForCurrentSequence(expected: Int, highestAvailable: Int)
    case missingCurrentOccurrence(id: UUID, sequence: Int)
    case currentOccurrenceLinkedElsewhere(id: UUID)
    case noActiveTodoAtCurrentSequence(Int)
    case unknownItemType(String)
}

nonisolated struct SyncPendingTemplate: Equatable, Sendable {
    let templateID: UUID
    let reason: SyncPendingReason
}

nonisolated enum SyncReconciliationMutation: Equatable, Sendable {
    case assignPhysicalID(
        record: SyncRecordReference,
        physicalID: UUID
    )
    case mergeDuplicate(
        duplicate: SyncRecordReference,
        canonical: SyncRecordReference
    )
    case attachTodo(
        todo: SyncRecordReference,
        template: SyncRecordReference
    )
    case attachEvent(
        event: SyncRecordReference,
        template: SyncRecordReference
    )
    case completeTodo(record: SyncRecordReference, completedAt: Date)
    case updateTemplate(
        record: SyncRecordReference,
        currentItemID: UUID,
        currentSequence: Int
    )
    case delete(record: SyncRecordReference)
}

nonisolated struct SyncReconciliationReport: Equatable, Sendable {
    let duplicateProjectsRemoved: Int
    let duplicateTodosRemoved: Int
    let duplicateEventsRemoved: Int
    let duplicateTemplatesRemoved: Int
    let recurrenceConflictsRepaired: Int
    let recurrenceLinksRepaired: Int
    let syncRecordIDsAssigned: Int
    let pendingTemplates: Int

    init(
        duplicateProjectsRemoved: Int = 0,
        duplicateTodosRemoved: Int = 0,
        duplicateEventsRemoved: Int = 0,
        duplicateTemplatesRemoved: Int = 0,
        recurrenceConflictsRepaired: Int = 0,
        recurrenceLinksRepaired: Int = 0,
        syncRecordIDsAssigned: Int = 0,
        pendingTemplates: Int = 0
    ) {
        self.duplicateProjectsRemoved = duplicateProjectsRemoved
        self.duplicateTodosRemoved = duplicateTodosRemoved
        self.duplicateEventsRemoved = duplicateEventsRemoved
        self.duplicateTemplatesRemoved = duplicateTemplatesRemoved
        self.recurrenceConflictsRepaired = recurrenceConflictsRepaired
        self.recurrenceLinksRepaired = recurrenceLinksRepaired
        self.syncRecordIDsAssigned = syncRecordIDsAssigned
        self.pendingTemplates = pendingTemplates
    }

    var madeChanges: Bool {
        duplicateProjectsRemoved > 0
            || duplicateTodosRemoved > 0
            || duplicateEventsRemoved > 0
            || duplicateTemplatesRemoved > 0
            || recurrenceConflictsRepaired > 0
            || recurrenceLinksRepaired > 0
            || syncRecordIDsAssigned > 0
    }
}

nonisolated struct SyncReconciliationPlan: Equatable, Sendable {
    let mutations: [SyncReconciliationMutation]
    let pendingTemplates: [SyncPendingTemplate]
    let transactionDate: Date
    let report: SyncReconciliationReport

    var hasChanges: Bool {
        !mutations.isEmpty
    }
}
