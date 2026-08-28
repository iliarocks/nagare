import Foundation

nonisolated enum ProjectPriority:
    Int,
    Codable,
    CaseIterable,
    Comparable,
    Hashable,
    Sendable
{
    case low = 0
    case normal = 1
    case high = 2

    static let displayOrder: [ProjectPriority] = [.high, .normal, .low]

    init(isPriority: Bool) {
        self = isPriority ? .high : .normal
    }

    var higher: ProjectPriority? {
        ProjectPriority(rawValue: rawValue + 1)
    }

    var lower: ProjectPriority? {
        ProjectPriority(rawValue: rawValue - 1)
    }

    static func < (lhs: ProjectPriority, rhs: ProjectPriority) -> Bool {
        lhs.rawValue < rhs.rawValue
    }
}

/// Immutable application data. Persistent framework objects never cross the
/// repository boundary; identity is always a replicated semantic UUID.
nonisolated struct TodoRecordSnapshot: Hashable, Sendable, Identifiable {
    let id: UUID
    let syncRecordID: UUID?
    let createdAt: Date
    let modifiedAt: Date?
    let title: String
    let notes: String?
    let scheduledDate: Date
    let includesTime: Bool
    let endDate: Date?
    let calendarIdentifier: String?
    let completedAt: Date?
    let order: String
    let projectOrder: String?
    let recurrenceSequence: Int?
    let recurrenceTemplateID: UUID?
    let projectID: UUID?

    var isCompleted: Bool { completedAt != nil }

    var orderingSnapshot: ItemSnapshot {
        ItemSnapshot(
            id: id,
            scheduledDate: scheduledDate,
            includesTime: includesTime,
            endDate: endDate,
            completedAt: completedAt,
            createdAt: createdAt,
            order: order,
            projectID: projectID,
            projectOrder: projectOrder
        )
    }

    static func ordered(
        _ todos: [TodoRecordSnapshot]
    ) -> [TodoRecordSnapshot] {
        todos.sorted {
            if $0.order != $1.order { return $0.order < $1.order }
            return $0.id.uuidString < $1.id.uuidString
        }
    }

    static func orderedInProject(
        _ todos: [TodoRecordSnapshot]
    ) -> [TodoRecordSnapshot] {
        todos.sorted {
            switch ($0.projectOrder, $1.projectOrder) {
            case let (.some(first), .some(second)) where first != second:
                return first < second
            case (.some, .none):
                return true
            case (.none, .some):
                return false
            default:
                return $0.id.uuidString < $1.id.uuidString
            }
        }
    }
}

/// “Item” remains useful UI language, but it is no longer a sum type.
typealias ItemRecordSnapshot = TodoRecordSnapshot

nonisolated struct ProjectRecordSnapshot: Hashable, Sendable, Identifiable {
    let id: UUID
    let syncRecordID: UUID?
    let createdAt: Date
    let modifiedAt: Date?
    let title: String
    let notes: String?
    let priority: ProjectPriority
    let order: String

    var isPriority: Bool { priority == .high }

    init(
        id: UUID,
        syncRecordID: UUID?,
        createdAt: Date,
        modifiedAt: Date?,
        title: String,
        notes: String?,
        priority: ProjectPriority,
        order: String
    ) {
        self.id = id
        self.syncRecordID = syncRecordID
        self.createdAt = createdAt
        self.modifiedAt = modifiedAt
        self.title = title
        self.notes = notes
        self.priority = priority
        self.order = order
    }

    init(
        id: UUID,
        syncRecordID: UUID?,
        createdAt: Date,
        modifiedAt: Date?,
        title: String,
        notes: String?,
        isPriority: Bool,
        order: String
    ) {
        self.init(
            id: id,
            syncRecordID: syncRecordID,
            createdAt: createdAt,
            modifiedAt: modifiedAt,
            title: title,
            notes: notes,
            priority: ProjectPriority(isPriority: isPriority),
            order: order
        )
    }
}

nonisolated struct RecurrenceTemplateRecordSnapshot:
    Hashable,
    Sendable,
    Identifiable
{
    let id: UUID
    let syncRecordID: UUID?
    let createdAt: Date
    let modifiedAt: Date?
    let title: String
    let notes: String?
    let modeRawValue: String
    let unitRawValue: String
    let interval: Int
    let anchors: [Int]
    let reference: Date?
    let startTimeSeconds: Int?
    let endTimeSeconds: Int?
    let currentItemID: UUID
    let currentSequence: Int
    let currentScheduledDate: Date?
    let projectID: UUID?
}

nonisolated struct NagareDataSnapshot: Equatable, Sendable {
    let projects: [ProjectRecordSnapshot]
    let todos: [TodoRecordSnapshot]
    let recurrenceTemplates: [RecurrenceTemplateRecordSnapshot]

    static let empty = NagareDataSnapshot(
        projects: [],
        todos: [],
        recurrenceTemplates: []
    )

    var projectsByID: [UUID: ProjectRecordSnapshot] {
        Dictionary(
            projects.map { ($0.id, $0) },
            uniquingKeysWith: preferredProject
        )
    }

    var todosByID: [UUID: TodoRecordSnapshot] {
        Dictionary(
            todos.map { ($0.id, $0) },
            uniquingKeysWith: preferredTodo
        )
    }

    var itemsByID: [UUID: TodoRecordSnapshot] { todosByID }

    var templatesByID: [UUID: RecurrenceTemplateRecordSnapshot] {
        Dictionary(
            recurrenceTemplates.map { ($0.id, $0) },
            uniquingKeysWith: preferredTemplate
        )
    }

    var canonicalProjects: [ProjectRecordSnapshot] {
        projectsByID.values.sorted { $0.id.uuidString < $1.id.uuidString }
    }

    var canonicalTodos: [TodoRecordSnapshot] {
        todosByID.values.sorted { $0.id.uuidString < $1.id.uuidString }
    }

    var canonicalRecurrenceTemplates: [RecurrenceTemplateRecordSnapshot] {
        templatesByID.values.sorted { $0.id.uuidString < $1.id.uuidString }
    }

    func note(for id: NoteRecordID) -> NoteRecordSnapshot? {
        switch id {
        case .todo(let id):
            todosByID[id].map(NoteRecordSnapshot.todo)
        case .recurrenceTemplate(let id):
            templatesByID[id].map(NoteRecordSnapshot.recurrenceTemplate)
        }
    }

    func currentItem(
        for template: RecurrenceTemplateRecordSnapshot
    ) -> TodoRecordSnapshot? {
        todos.first {
            $0.id == template.currentItemID && $0.completedAt == nil
        }
    }

    func currentProjectOrder(
        for template: RecurrenceTemplateRecordSnapshot
    ) -> String {
        currentItem(for: template)?.projectOrder ?? ""
    }

    var recurrenceProjectionInput: RecurrenceProjectionInput {
        RecurrenceProjectionInput(
            templates: recurrenceTemplates.map {
                RecurrenceProjectionTemplateSnapshot(
                    metadata: metadata(
                        kind: .recurrenceTemplate,
                        id: $0.id,
                        syncRecordID: $0.syncRecordID,
                        createdAt: $0.createdAt,
                        modifiedAt: $0.modifiedAt,
                        stableTieBreaker: templateTieBreaker($0)
                    ),
                    modeRawValue: $0.modeRawValue,
                    unitRawValue: $0.unitRawValue,
                    interval: $0.interval,
                    anchors: $0.anchors,
                    reference: $0.reference,
                    startTimeSeconds: $0.startTimeSeconds,
                    endTimeSeconds: $0.endTimeSeconds,
                    currentItemID: $0.currentItemID,
                    currentSequence: $0.currentSequence
                )
            },
            occurrences: todos.map {
                RecurrenceProjectionOccurrenceSnapshot(
                    metadata: metadata(
                        kind: .todo,
                        id: $0.id,
                        syncRecordID: $0.syncRecordID,
                        createdAt: $0.createdAt,
                        modifiedAt: $0.modifiedAt,
                        stableTieBreaker: todoTieBreaker($0)
                    ),
                    scheduledDate: $0.scheduledDate,
                    completedAt: $0.completedAt,
                    order: $0.order,
                    recurrenceSequence: $0.recurrenceSequence,
                    recurrenceTemplateID: $0.recurrenceTemplateID
                )
            }
        )
    }

    private func metadata(
        kind: SyncEntityKind,
        id: UUID,
        syncRecordID: UUID?,
        createdAt: Date,
        modifiedAt: Date?,
        stableTieBreaker: [String]
    ) -> SyncRecordMetadata {
        SyncRecordMetadata(
            reference: SyncRecordReference(
                kind: kind,
                localID: (syncRecordID ?? id).uuidString
            ),
            semanticID: id,
            physicalID: syncRecordID,
            createdAt: createdAt,
            modifiedAt: modifiedAt,
            stableTieBreaker: stableTieBreaker
        )
    }

    private func preferredProject(
        _ first: ProjectRecordSnapshot,
        _ second: ProjectRecordSnapshot
    ) -> ProjectRecordSnapshot {
        preferred(
            first,
            second,
            firstMetadata: metadata(
                kind: .project,
                id: first.id,
                syncRecordID: first.syncRecordID,
                createdAt: first.createdAt,
                modifiedAt: first.modifiedAt,
                stableTieBreaker: projectTieBreaker(first)
            ),
            secondMetadata: metadata(
                kind: .project,
                id: second.id,
                syncRecordID: second.syncRecordID,
                createdAt: second.createdAt,
                modifiedAt: second.modifiedAt,
                stableTieBreaker: projectTieBreaker(second)
            )
        )
    }

    private func preferredTodo(
        _ first: TodoRecordSnapshot,
        _ second: TodoRecordSnapshot
    ) -> TodoRecordSnapshot {
        preferred(
            first,
            second,
            firstMetadata: metadata(
                kind: .todo,
                id: first.id,
                syncRecordID: first.syncRecordID,
                createdAt: first.createdAt,
                modifiedAt: first.modifiedAt,
                stableTieBreaker: todoTieBreaker(first)
            ),
            secondMetadata: metadata(
                kind: .todo,
                id: second.id,
                syncRecordID: second.syncRecordID,
                createdAt: second.createdAt,
                modifiedAt: second.modifiedAt,
                stableTieBreaker: todoTieBreaker(second)
            )
        )
    }

    private func preferredTemplate(
        _ first: RecurrenceTemplateRecordSnapshot,
        _ second: RecurrenceTemplateRecordSnapshot
    ) -> RecurrenceTemplateRecordSnapshot {
        preferred(
            first,
            second,
            firstMetadata: metadata(
                kind: .recurrenceTemplate,
                id: first.id,
                syncRecordID: first.syncRecordID,
                createdAt: first.createdAt,
                modifiedAt: first.modifiedAt,
                stableTieBreaker: templateTieBreaker(first)
            ),
            secondMetadata: metadata(
                kind: .recurrenceTemplate,
                id: second.id,
                syncRecordID: second.syncRecordID,
                createdAt: second.createdAt,
                modifiedAt: second.modifiedAt,
                stableTieBreaker: templateTieBreaker(second)
            )
        )
    }

    private func preferred<Record>(
        _ first: Record,
        _ second: Record,
        firstMetadata: SyncRecordMetadata,
        secondMetadata: SyncRecordMetadata
    ) -> Record {
        SyncRecordOrdering.isLowerPriority(firstMetadata, than: secondMetadata)
            ? second
            : first
    }

    private func projectTieBreaker(
        _ project: ProjectRecordSnapshot
    ) -> [String] {
        [
            SyncStableValue.encode(project.title),
            SyncStableValue.encode(project.notes),
            SyncStableValue.encode(project.priority.rawValue),
            SyncStableValue.encode(project.order)
        ]
    }

    private func todoTieBreaker(_ todo: TodoRecordSnapshot) -> [String] {
        [
            SyncStableValue.encode(todo.title),
            SyncStableValue.encode(todo.notes),
            SyncStableValue.encode(todo.scheduledDate),
            SyncStableValue.encode(todo.includesTime),
            SyncStableValue.encode(todo.endDate),
            SyncStableValue.encode(todo.calendarIdentifier),
            SyncStableValue.encode(todo.completedAt),
            SyncStableValue.encode(todo.order),
            SyncStableValue.encode(todo.projectOrder),
            SyncStableValue.encode(todo.recurrenceSequence),
            SyncStableValue.encode(todo.recurrenceTemplateID),
            SyncStableValue.encode(todo.projectID)
        ]
    }

    private func templateTieBreaker(
        _ template: RecurrenceTemplateRecordSnapshot
    ) -> [String] {
        [
            SyncStableValue.encode(template.title),
            SyncStableValue.encode(template.notes),
            SyncStableValue.encode(template.modeRawValue),
            SyncStableValue.encode(template.unitRawValue),
            SyncStableValue.encode(template.interval),
            SyncStableValue.encode(template.anchors),
            SyncStableValue.encode(template.reference),
            SyncStableValue.encode(template.startTimeSeconds),
            SyncStableValue.encode(template.endTimeSeconds),
            SyncStableValue.encode(template.currentItemID),
            SyncStableValue.encode(template.currentSequence),
            SyncStableValue.encode(template.projectID)
        ]
    }
}

nonisolated enum NoteRecordID: Hashable, Sendable {
    case todo(UUID)
    case recurrenceTemplate(UUID)
}

nonisolated enum NoteRecordSnapshot: Hashable, Sendable, Identifiable {
    case todo(TodoRecordSnapshot)
    case recurrenceTemplate(RecurrenceTemplateRecordSnapshot)

    var id: NoteRecordID {
        switch self {
        case .todo(let todo): .todo(todo.id)
        case .recurrenceTemplate(let template):
            .recurrenceTemplate(template.id)
        }
    }

    var title: String {
        switch self {
        case .todo(let todo): todo.title
        case .recurrenceTemplate(let template): template.title
        }
    }

    var notes: String? {
        switch self {
        case .todo(let todo): todo.notes
        case .recurrenceTemplate(let template): template.notes
        }
    }

    var projectID: UUID? {
        switch self {
        case .todo(let todo): todo.projectID
        case .recurrenceTemplate(let template): template.projectID
        }
    }
}

nonisolated enum ProjectMoveRecordID: Hashable, Sendable {
    case item(UUID)
    case recurrenceTemplate(UUID)
}

/// A complete immutable intent to create or revise one todo. The UI owns this
/// value; the persistence adapter owns all record lookup and mutation.
nonisolated struct ItemDraft: Sendable {
    let title: String
    let notes: String?
    let scheduledDate: Date
    let includesTime: Bool
    let endDate: Date?
    let projectID: UUID?
    let recurrenceRule: RecurrenceRule?
    let startTimeSeconds: Int?
    let endTimeSeconds: Int?

    init(
        title: String,
        notes: String?,
        scheduledDate: Date,
        includesTime: Bool = false,
        endDate: Date? = nil,
        projectID: UUID?,
        recurrenceRule: RecurrenceRule?,
        startTimeSeconds: Int? = nil,
        endTimeSeconds: Int? = nil
    ) {
        self.title = title
        self.notes = notes
        self.scheduledDate = scheduledDate
        self.includesTime = includesTime
        self.endDate = includesTime ? endDate : nil
        self.projectID = projectID
        self.recurrenceRule = recurrenceRule
        self.startTimeSeconds = includesTime ? startTimeSeconds : nil
        self.endTimeSeconds = includesTime ? endTimeSeconds : nil
    }
}

nonisolated struct ProjectDraft: Hashable, Sendable {
    let title: String
    let notes: String?
}

nonisolated struct ItemUpsertPlan: Sendable {
    let draft: ItemDraft
    let existingID: UUID?
    let order: String
    let orderRepairs: [ItemOrderingChange]
    let projectOrder: String?
    let projectOrderRepairs: [ProjectItemOrderingChange]
}

nonisolated struct ProjectUpsertPlan: Sendable {
    let draft: ProjectDraft
    let existingID: UUID?
    let order: String
    let orderRepairs: [ProjectOrderingChange]
}

nonisolated struct ProjectAssignmentPlan: Sendable {
    let itemID: UUID
    let recurrenceTemplateID: UUID?
    let projectID: UUID?
    let projectOrder: String?
    let projectOrderRepairs: [ProjectItemOrderingChange]
}

nonisolated struct ProjectAssignmentBatchEntry: Sendable {
    let itemID: UUID
    let recurrenceTemplateID: UUID?
    let projectOrder: String?
}

nonisolated struct ProjectAssignmentBatchPlan: Sendable {
    let projectID: UUID?
    let entries: [ProjectAssignmentBatchEntry]
    let projectOrderChanges: [ProjectItemOrderingChange]
}

nonisolated struct TodoReinstatementPlan: Sendable {
    let id: UUID
    let scheduledDate: Date
    let order: String
    let orderRepairs: [ItemOrderingChange]
    let projectOrder: String?
    let projectOrderRepairs: [ProjectItemOrderingChange]
}
