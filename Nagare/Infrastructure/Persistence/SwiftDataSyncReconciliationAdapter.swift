import Foundation
import SwiftData

/// SwiftData translation and mutation adapter. It deliberately contains no
/// canonicalization, conflict, recurrence, or partial-import policy.
@MainActor
final class SwiftDataSyncReconciliationAdapter: SyncReconciliationPersistence {
    private let context: ModelContext
    private var projects: [SyncRecordReference: Project] = [:]
    private var templates: [SyncRecordReference: RecurrenceTemplate] = [:]
    private var todos: [SyncRecordReference: Todo] = [:]
    private var events: [SyncRecordReference: Event] = [:]

    init(context: ModelContext) {
        self.context = context
    }

    func loadSyncGraph() throws -> SyncGraphSnapshot {
        do {
            let projectRecords = try context.fetch(FetchDescriptor<Project>())
            let templateRecords = try context.fetch(
                FetchDescriptor<RecurrenceTemplate>()
            )
            let todoRecords = try context.fetch(FetchDescriptor<Todo>())
            let eventRecords = try context.fetch(FetchDescriptor<Event>())

            projects = index(projectRecords, kind: .project)
            templates = index(templateRecords, kind: .recurrenceTemplate)
            todos = index(todoRecords, kind: .todo)
            events = index(eventRecords, kind: .event)

            return SyncGraphSnapshot(
                projects: projectRecords.map(
                    SwiftDataSyncSnapshotMapper.project
                ),
                recurrenceTemplates: templateRecords.map(
                    SwiftDataSyncSnapshotMapper.recurrenceTemplate
                ),
                todos: todoRecords.map(SwiftDataSyncSnapshotMapper.todo),
                events: eventRecords.map(SwiftDataSyncSnapshotMapper.event)
            )
        } catch {
            throw SyncReconciliationPersistenceError.loadFailed(
                error.localizedDescription
            )
        }
    }

    func apply(_ mutations: [SyncReconciliationMutation]) throws {
        do {
            for mutation in mutations {
                try apply(mutation)
            }
        } catch let error as SyncReconciliationPersistenceError {
            throw error
        } catch {
            throw SyncReconciliationPersistenceError.applyFailed(
                error.localizedDescription
            )
        }
    }

    func save(at transactionDate: Date) throws {
        do {
            try SwiftDataTransaction.save(context, at: transactionDate)
        } catch {
            throw SyncReconciliationPersistenceError.saveFailed(
                error.localizedDescription
            )
        }
    }

    func rollback() {
        context.rollback()
    }

    private func apply(_ mutation: SyncReconciliationMutation) throws {
        switch mutation {
        case .assignPhysicalID(let reference, let physicalID):
            try syncRecord(for: reference).syncRecordID = physicalID

        case .mergeDuplicate(let duplicate, let canonical):
            try merge(duplicate: duplicate, into: canonical)

        case .attachTodo(let todoReference, let templateReference):
            let todo = try require(todos[todoReference], todoReference)
            let template = try require(
                templates[templateReference],
                templateReference
            )
            todo.recurrenceTemplate = template

        case .attachEvent(let eventReference, let templateReference):
            let event = try require(events[eventReference], eventReference)
            let template = try require(
                templates[templateReference],
                templateReference
            )
            event.recurrenceTemplate = template

        case .completeTodo(let reference, let completedAt):
            try require(todos[reference], reference).completedAt = completedAt

        case .updateTemplate(
            let reference,
            let currentItemID,
            let currentSequence
        ):
            let template = try require(templates[reference], reference)
            template.currentItemID = currentItemID
            template.currentSequence = currentSequence

        case .delete(let reference):
            try delete(reference)
        }
    }

    private func merge(
        duplicate: SyncRecordReference,
        into canonical: SyncRecordReference
    ) throws {
        guard duplicate.kind == canonical.kind else {
            throw adapterError(
                "A duplicate and its canonical record have different types."
            )
        }

        switch duplicate.kind {
        case .project:
            let old = try require(projects[duplicate], duplicate)
            let survivor = try require(projects[canonical], canonical)
            for todo in todos.values where todo.project === old {
                todo.project = survivor
            }
            for event in events.values where event.project === old {
                event.project = survivor
            }
            for template in templates.values where template.project === old {
                template.project = survivor
            }
            context.delete(old)

        case .recurrenceTemplate:
            let old = try require(templates[duplicate], duplicate)
            let survivor = try require(templates[canonical], canonical)
            for todo in todos.values where todo.recurrenceTemplate === old {
                todo.recurrenceTemplate = survivor
            }
            for event in events.values where event.recurrenceTemplate === old {
                event.recurrenceTemplate = survivor
            }
            context.delete(old)

        case .todo:
            context.delete(try require(todos[duplicate], duplicate))

        case .event:
            context.delete(try require(events[duplicate], duplicate))
        }
    }

    private func delete(_ reference: SyncRecordReference) throws {
        switch reference.kind {
        case .project:
            context.delete(try require(projects[reference], reference))
        case .recurrenceTemplate:
            context.delete(try require(templates[reference], reference))
        case .todo:
            context.delete(try require(todos[reference], reference))
        case .event:
            context.delete(try require(events[reference], reference))
        }
    }

    private func syncRecord(
        for reference: SyncRecordReference
    ) throws -> any SyncRecord {
        switch reference.kind {
        case .project:
            try require(projects[reference], reference)
        case .recurrenceTemplate:
            try require(templates[reference], reference)
        case .todo:
            try require(todos[reference], reference)
        case .event:
            try require(events[reference], reference)
        }
    }

    private func require<Record>(
        _ record: Record?,
        _ reference: SyncRecordReference
    ) throws -> Record {
        guard let record else {
            throw adapterError(
                "The \(reference.kind.rawValue) record no longer exists."
            )
        }
        return record
    }

    private func adapterError(
        _ message: String
    ) -> SyncReconciliationPersistenceError {
        .applyFailed(message)
    }

    private func index<Record>(
        _ records: [Record],
        kind: SyncEntityKind
    ) -> [SyncRecordReference: Record] where Record: PersistentModel {
        Dictionary(
            uniqueKeysWithValues: records.map {
                (
                    SwiftDataSyncSnapshotMapper.reference(
                        for: $0,
                        kind: kind
                    ),
                    $0
                )
            }
        )
    }
}
