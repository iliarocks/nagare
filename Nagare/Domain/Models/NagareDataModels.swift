import Foundation

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
    let completedAt: Date?
    let order: String
    let projectOrder: String?
    let recurrenceSequence: Int?
    let recurrenceTemplateID: UUID?
    let projectID: UUID?

}

nonisolated struct EventRecordSnapshot: Hashable, Sendable, Identifiable {
    let id: UUID
    let syncRecordID: UUID?
    let createdAt: Date
    let modifiedAt: Date?
    let title: String
    let notes: String?
    let scheduledDate: Date
    let endDate: Date?
    let calendarIdentifier: String?
    let order: String
    let projectOrder: String?
    let recurrenceSequence: Int?
    let recurrenceTemplateID: UUID?
    let projectID: UUID?

}

nonisolated struct ProjectRecordSnapshot: Hashable, Sendable, Identifiable {
    let id: UUID
    let syncRecordID: UUID?
    let createdAt: Date
    let modifiedAt: Date?
    let title: String
    let notes: String?
    let isPriority: Bool
    let order: String

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
    let itemTypeRawValue: String
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

    var itemType: RecurrenceItemType? {
        RecurrenceItemType(rawValue: itemTypeRawValue)
    }
}

nonisolated struct NagareDataSnapshot: Equatable, Sendable {
    let projects: [ProjectRecordSnapshot]
    let todos: [TodoRecordSnapshot]
    let events: [EventRecordSnapshot]
    let recurrenceTemplates: [RecurrenceTemplateRecordSnapshot]

    static let empty = NagareDataSnapshot(
        projects: [],
        todos: [],
        events: [],
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

    var eventsByID: [UUID: EventRecordSnapshot] {
        Dictionary(
            events.map { ($0.id, $0) },
            uniquingKeysWith: preferredEvent
        )
    }

    var templatesByID: [UUID: RecurrenceTemplateRecordSnapshot] {
        Dictionary(
            recurrenceTemplates.map { ($0.id, $0) },
            uniquingKeysWith: preferredTemplate
        )
    }

    var itemsByID: [ItemID: ItemRecordSnapshot] {
        var result = Dictionary(
            uniqueKeysWithValues: todosByID.map {
                (ItemID.todo($0.key), ItemRecordSnapshot.todo($0.value))
            }
        )
        result.merge(
            eventsByID.map {
                (ItemID.event($0.key), ItemRecordSnapshot.event($0.value))
            },
            uniquingKeysWith: { current, _ in current }
        )
        return result
    }

    var canonicalProjects: [ProjectRecordSnapshot] {
        projectsByID.values.sorted { $0.id.uuidString < $1.id.uuidString }
    }

    var canonicalTodos: [TodoRecordSnapshot] {
        todosByID.values.sorted { $0.id.uuidString < $1.id.uuidString }
    }

    var canonicalEvents: [EventRecordSnapshot] {
        eventsByID.values.sorted { $0.id.uuidString < $1.id.uuidString }
    }

    var canonicalRecurrenceTemplates: [RecurrenceTemplateRecordSnapshot] {
        templatesByID.values.sorted { $0.id.uuidString < $1.id.uuidString }
    }

    func note(for id: NoteRecordID) -> NoteRecordSnapshot? {
        switch id {
        case .todo(let id):
            todosByID[id].map(NoteRecordSnapshot.todo)
        case .event(let id):
            eventsByID[id].map(NoteRecordSnapshot.event)
        case .recurrenceTemplate(let id):
            templatesByID[id].map(NoteRecordSnapshot.recurrenceTemplate)
        }
    }

    func currentItem(
        for template: RecurrenceTemplateRecordSnapshot
    ) -> ItemRecordSnapshot? {
        switch template.itemType {
        case .todo:
            todos.first {
                $0.id == template.currentItemID && $0.completedAt == nil
            }.map(ItemRecordSnapshot.todo)
        case .event:
            events.first {
                $0.id == template.currentItemID
            }.map(ItemRecordSnapshot.event)
        case nil:
            nil
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
                    itemTypeRawValue: $0.itemTypeRawValue,
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
                    itemType: .todo,
                    scheduledDate: $0.scheduledDate,
                    completedAt: $0.completedAt,
                    order: $0.order,
                    recurrenceSequence: $0.recurrenceSequence,
                    recurrenceTemplateID: $0.recurrenceTemplateID
                )
            } + events.map {
                RecurrenceProjectionOccurrenceSnapshot(
                    metadata: metadata(
                        kind: .event,
                        id: $0.id,
                        syncRecordID: $0.syncRecordID,
                        createdAt: $0.createdAt,
                        modifiedAt: $0.modifiedAt,
                        stableTieBreaker: eventTieBreaker($0)
                    ),
                    itemType: .event,
                    scheduledDate: $0.scheduledDate,
                    completedAt: nil,
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

    private func preferredEvent(
        _ first: EventRecordSnapshot,
        _ second: EventRecordSnapshot
    ) -> EventRecordSnapshot {
        preferred(
            first,
            second,
            firstMetadata: metadata(
                kind: .event,
                id: first.id,
                syncRecordID: first.syncRecordID,
                createdAt: first.createdAt,
                modifiedAt: first.modifiedAt,
                stableTieBreaker: eventTieBreaker(first)
            ),
            secondMetadata: metadata(
                kind: .event,
                id: second.id,
                syncRecordID: second.syncRecordID,
                createdAt: second.createdAt,
                modifiedAt: second.modifiedAt,
                stableTieBreaker: eventTieBreaker(second)
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
            SyncStableValue.encode(project.isPriority),
            SyncStableValue.encode(project.order)
        ]
    }

    private func todoTieBreaker(_ todo: TodoRecordSnapshot) -> [String] {
        [
            SyncStableValue.encode(todo.title),
            SyncStableValue.encode(todo.notes),
            SyncStableValue.encode(todo.scheduledDate),
            SyncStableValue.encode(todo.completedAt),
            SyncStableValue.encode(todo.order),
            SyncStableValue.encode(todo.projectOrder),
            SyncStableValue.encode(todo.recurrenceSequence),
            SyncStableValue.encode(todo.recurrenceTemplateID),
            SyncStableValue.encode(todo.projectID)
        ]
    }

    private func eventTieBreaker(_ event: EventRecordSnapshot) -> [String] {
        [
            SyncStableValue.encode(event.title),
            SyncStableValue.encode(event.notes),
            SyncStableValue.encode(event.scheduledDate),
            SyncStableValue.encode(event.endDate),
            SyncStableValue.encode(event.calendarIdentifier),
            SyncStableValue.encode(event.order),
            SyncStableValue.encode(event.projectOrder),
            SyncStableValue.encode(event.recurrenceSequence),
            SyncStableValue.encode(event.recurrenceTemplateID),
            SyncStableValue.encode(event.projectID)
        ]
    }

    private func templateTieBreaker(
        _ template: RecurrenceTemplateRecordSnapshot
    ) -> [String] {
        [
            SyncStableValue.encode(template.itemTypeRawValue),
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

nonisolated enum ItemRecordSnapshot: Hashable, Sendable, Identifiable {
    case todo(TodoRecordSnapshot)
    case event(EventRecordSnapshot)

    var id: ItemID {
        switch self {
        case .todo(let todo): .todo(todo.id)
        case .event(let event): .event(event.id)
        }
    }

    var title: String {
        switch self {
        case .todo(let todo): todo.title
        case .event(let event): event.title
        }
    }

    var notes: String? {
        switch self {
        case .todo(let todo): todo.notes
        case .event(let event): event.notes
        }
    }

    var scheduledDate: Date {
        switch self {
        case .todo(let todo): todo.scheduledDate
        case .event(let event): event.scheduledDate
        }
    }

    var endDate: Date? {
        switch self {
        case .todo: nil
        case .event(let event): event.endDate
        }
    }

    var order: String {
        switch self {
        case .todo(let todo): todo.order
        case .event(let event): event.order
        }
    }

    var projectID: UUID? {
        switch self {
        case .todo(let todo): todo.projectID
        case .event(let event): event.projectID
        }
    }

    var projectOrder: String? {
        switch self {
        case .todo(let todo): todo.projectOrder
        case .event(let event): event.projectOrder
        }
    }

    var isCompleted: Bool {
        switch self {
        case .todo(let todo): todo.completedAt != nil
        case .event: false
        }
    }

    var orderingSnapshot: ItemSnapshot {
        switch self {
        case .todo(let todo):
            ItemSnapshot(
                id: id,
                kind: .todo,
                scheduledDate: todo.scheduledDate,
                endDate: nil,
                completedAt: todo.completedAt,
                createdAt: todo.createdAt,
                order: todo.order,
                projectID: todo.projectID,
                projectOrder: todo.projectOrder
            )
        case .event(let event):
            ItemSnapshot(
                id: id,
                kind: .event,
                scheduledDate: event.scheduledDate,
                endDate: event.endDate,
                completedAt: nil,
                createdAt: event.createdAt,
                order: event.order,
                projectID: event.projectID,
                projectOrder: event.projectOrder
            )
        }
    }

    static func ordered(
        todos: [TodoRecordSnapshot],
        events: [EventRecordSnapshot]
    ) -> [ItemRecordSnapshot] {
        (todos.map(Self.todo) + events.map(Self.event)).sorted {
            if $0.order != $1.order { return $0.order < $1.order }
            return $0.id.description < $1.id.description
        }
    }

    static func orderedInProject(
        todos: [TodoRecordSnapshot],
        events: [EventRecordSnapshot]
    ) -> [ItemRecordSnapshot] {
        (todos.map(Self.todo) + events.map(Self.event)).sorted {
            switch ($0.projectOrder, $1.projectOrder) {
            case let (.some(first), .some(second)) where first != second:
                return first < second
            case (.some, .none):
                return true
            case (.none, .some):
                return false
            default:
                return $0.id.description < $1.id.description
            }
        }
    }
}

nonisolated enum NoteRecordID: Hashable, Sendable {
    case todo(UUID)
    case event(UUID)
    case recurrenceTemplate(UUID)
}

nonisolated enum NoteRecordSnapshot: Hashable, Sendable, Identifiable {
    case todo(TodoRecordSnapshot)
    case event(EventRecordSnapshot)
    case recurrenceTemplate(RecurrenceTemplateRecordSnapshot)

    var id: NoteRecordID {
        switch self {
        case .todo(let todo): .todo(todo.id)
        case .event(let event): .event(event.id)
        case .recurrenceTemplate(let template):
            .recurrenceTemplate(template.id)
        }
    }

    var title: String {
        switch self {
        case .todo(let todo): todo.title
        case .event(let event): event.title
        case .recurrenceTemplate(let template): template.title
        }
    }

    var notes: String? {
        switch self {
        case .todo(let todo): todo.notes
        case .event(let event): event.notes
        case .recurrenceTemplate(let template): template.notes
        }
    }

    var projectID: UUID? {
        switch self {
        case .todo(let todo): todo.projectID
        case .event(let event): event.projectID
        case .recurrenceTemplate(let template): template.projectID
        }
    }
}

nonisolated enum ProjectMoveRecordID: Hashable, Sendable {
    case item(ItemID)
    case recurrenceTemplate(UUID)
}

nonisolated enum ItemDraftKind: Hashable, Sendable {
    case todo
    case event
}

/// A complete immutable intent to create or revise one item. The UI owns this
/// value; the persistence adapter owns all record lookup and mutation.
nonisolated struct ItemDraft: Sendable {
    let kind: ItemDraftKind
    let title: String
    let notes: String?
    let scheduledDate: Date
    let endDate: Date?
    let projectID: UUID?
    let recurrenceRule: RecurrenceRule?
    let eventStartTimeSeconds: Int?
    let eventEndTimeSeconds: Int?
}

nonisolated struct ProjectDraft: Hashable, Sendable {
    let title: String
    let notes: String?
}

/// Fully planned write commands. Every order choice and repair is decided from
/// an immutable graph before the persistence boundary is entered.
nonisolated struct ItemUpsertPlan: Sendable {
    let draft: ItemDraft
    let existingID: ItemID?
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

nonisolated struct CalendarEventUpsertPlan: Sendable {
    let draft: ICalendarEventDraft
    let order: String
    let orderRepairs: [ItemOrderingChange]
}

nonisolated struct ProjectAssignmentPlan: Sendable {
    let itemID: ItemID
    let recurrenceTemplateID: UUID?
    let projectID: UUID?
    let projectOrder: String?
    let projectOrderRepairs: [ProjectItemOrderingChange]
}

nonisolated struct TodoReinstatementPlan: Sendable {
    let id: UUID
    let scheduledDate: Date
    let order: String
    let orderRepairs: [ItemOrderingChange]
    let projectOrder: String?
    let projectOrderRepairs: [ProjectItemOrderingChange]
}
