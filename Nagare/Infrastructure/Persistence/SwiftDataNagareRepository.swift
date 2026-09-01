import Foundation
import SwiftData

/// Razor-thin SwiftData boundary. Every operation creates a fresh context,
/// translates to or from immutable values, commits once, then releases every
/// managed object. Conflict and ordering policy never lives here.
@MainActor
final class SwiftDataNagareRepository:
    NagareDataReading,
    NagareDataWriting
{
    private let modelContainer: ModelContainer
    private let historyAuthor: String

    init(
        modelContainer: ModelContainer,
        historyAuthor: String = NagareCloud.localHistoryAuthor
    ) {
        self.modelContainer = modelContainer
        self.historyAuthor = historyAuthor
    }

    func upsertItem(
        _ plan: ItemUpsertPlan,
        at date: Date
    ) throws -> UUID {
        let context = makeContext()
        do {
            try applyItemOrdering(plan.orderRepairs, in: context)
            try applyProjectItemOrdering(
                plan.projectOrderRepairs,
                in: context
            )
            let item: Todo
            if let existingID = plan.existingID {
                item = try requireTodo(existingID, in: context)
                apply(plan.draft, to: item)
            } else {
                item = create(
                    plan.draft,
                    order: plan.order,
                    projectOrder: plan.projectOrder,
                    at: date,
                    in: context
                )
            }
            item.order = plan.order
            try applyProject(
                to: item,
                projectID: plan.draft.projectID,
                projectOrder: plan.projectOrder,
                in: context
            )
            try persistRecurrence(
                for: item,
                draft: plan.draft,
                at: date,
                in: context
            )
            return item.id
        } catch let error as NagareDataPersistenceError {
            throw error
        } catch {
            context.rollback()
            throw NagareDataPersistenceError.saveFailed(
                error.localizedDescription
            )
        }
    }

    func upsertProject(
        _ plan: ProjectUpsertPlan,
        at date: Date
    ) throws -> UUID {
        let context = makeContext()
        do {
            try applyProjectOrdering(plan.orderRepairs, in: context)
            if let existingID = plan.existingID {
                let project = try requireProject(existingID, in: context)
                project.title = plan.draft.title
                project.notes = plan.draft.notes
                try SwiftDataTransaction.save(context, at: date)
                return project.id
            }
            let project = Project(
                title: plan.draft.title,
                notes: plan.draft.notes,
                priority: .normal,
                order: plan.order,
                createdAt: date
            )
            context.insert(project)
            try SwiftDataTransaction.save(context, at: date)
            return project.id
        } catch let error as NagareDataPersistenceError {
            throw error
        } catch {
            context.rollback()
            throw NagareDataPersistenceError.saveFailed(
                error.localizedDescription
            )
        }
    }

    func load() throws -> NagareDataSnapshot {
        let context = makeContext()
        do {
            return NagareDataSnapshot(
                projects: try context.fetch(FetchDescriptor<Project>()).map {
                    ProjectRecordSnapshot(
                        id: $0.id,
                        syncRecordID: $0.syncRecordID,
                        createdAt: $0.createdAt,
                        modifiedAt: $0.modifiedAt,
                        title: $0.title,
                        notes: $0.notes,
                        priority: $0.priority,
                        order: $0.order
                    )
                },
                todos: try context.fetch(FetchDescriptor<Todo>()).map {
                    TodoRecordSnapshot(
                        id: $0.id,
                        syncRecordID: $0.syncRecordID,
                        createdAt: $0.createdAt,
                        modifiedAt: $0.modifiedAt,
                        title: $0.title,
                        notes: $0.notes,
                        scheduledDate: $0.scheduledDate,
                        includesTime: $0.includesTime,
                        endDate: $0.endDate,
                        calendarIdentifier: $0.calendarIdentifier,
                        completedAt: $0.completedAt,
                        order: $0.order,
                        projectOrder: $0.projectOrder,
                        recurrenceSequence: $0.recurrenceSequence,
                        recurrenceTemplateID: $0.recurrenceTemplate?.id,
                        projectID: $0.project?.id
                    )
                },
                recurrenceTemplates: try context.fetch(
                    FetchDescriptor<RecurrenceTemplate>()
                ).map {
                    RecurrenceTemplateRecordSnapshot(
                        id: $0.id,
                        syncRecordID: $0.syncRecordID,
                        createdAt: $0.createdAt,
                        modifiedAt: $0.modifiedAt,
                        title: $0.title,
                        notes: $0.notes,
                        modeRawValue: $0.modeRawValue,
                        unitRawValue: $0.unitRawValue,
                        interval: $0.interval,
                        anchors: $0.anchors,
                        reference: $0.reference,
                        repeatUntil: $0.repeatUntil,
                        startTimeSeconds: $0.startTimeSeconds,
                        endTimeSeconds: $0.endTimeSeconds,
                        currentItemID: $0.currentItemID,
                        currentSequence: $0.currentSequence,
                        currentScheduledDate: currentScheduledDate(for: $0),
                        projectID: $0.project?.id
                    )
                }
            )
        } catch {
            throw NagareDataPersistenceError.loadFailed(
                error.localizedDescription
            )
        }
    }

    func importData(
        _ plan: NagareDataImportPlan,
        at date: Date
    ) throws {
        let context = makeContext()
        do {
            let existingProjects = Dictionary(
                grouping: try context.fetch(FetchDescriptor<Project>()),
                by: \.id
            )
            let existingTodos = Dictionary(
                grouping: try context.fetch(FetchDescriptor<Todo>()),
                by: \.id
            )
            let existingTemplates = Dictionary(
                grouping: try context.fetch(
                    FetchDescriptor<RecurrenceTemplate>()
                ),
                by: \.id
            )

            var projectsByID: [UUID: Project] = [:]
            for source in plan.projects {
                let project = try existingRecord(
                    source.id,
                    in: existingProjects
                ) ?? Project(
                    id: source.id,
                    title: source.title,
                    notes: source.notes,
                    priority: source.priority,
                    order: source.order,
                    createdAt: source.createdAt
                )
                if project.modelContext == nil { context.insert(project) }
                project.createdAt = source.createdAt
                project.title = source.title
                project.notes = source.notes
                project.priority = source.priority
                project.order = source.order
                projectsByID[source.id] = project
            }

            var templatesByID: [UUID: RecurrenceTemplate] = [:]
            for source in plan.recurrenceTemplates {
                let record = source.record
                let template = try existingRecord(
                    record.id,
                    in: existingTemplates
                ) ?? RecurrenceTemplate(
                    id: record.id,
                    title: record.title,
                    notes: record.notes,
                    rule: source.rule,
                    startTimeSeconds: record.startTimeSeconds,
                    endTimeSeconds: record.endTimeSeconds,
                    currentItemID: record.currentItemID,
                    currentSequence: record.currentSequence,
                    createdAt: record.createdAt
                )
                if template.modelContext == nil { context.insert(template) }
                template.createdAt = record.createdAt
                template.title = record.title
                template.notes = record.notes
                template.modeRawValue = record.modeRawValue
                template.unitRawValue = record.unitRawValue
                template.interval = record.interval
                template.anchors = record.anchors
                template.reference = record.reference
                template.repeatUntil = record.repeatUntil
                template.startTimeSeconds = record.startTimeSeconds
                template.endTimeSeconds = record.endTimeSeconds
                template.currentItemID = record.currentItemID
                template.currentSequence = record.currentSequence
                template.project = try importedProject(
                    record.projectID,
                    in: projectsByID
                )
                templatesByID[record.id] = template
            }

            for source in plan.todos {
                let todo = try existingRecord(
                    source.id,
                    in: existingTodos
                ) ?? Todo(
                    id: source.id,
                    title: source.title,
                    notes: source.notes,
                    scheduledDate: source.scheduledDate,
                    includesTime: source.includesTime,
                    endDate: source.endDate,
                    calendarIdentifier: source.calendarIdentifier,
                    completedAt: source.completedAt,
                    createdAt: source.createdAt,
                    order: source.order,
                    projectOrder: source.projectOrder
                )
                if todo.modelContext == nil { context.insert(todo) }
                todo.createdAt = source.createdAt
                todo.title = source.title
                todo.notes = source.notes
                todo.scheduledDate = source.scheduledDate
                todo.includesTime = source.includesTime
                todo.endDate = source.includesTime ? source.endDate : nil
                todo.calendarIdentifier = source.calendarIdentifier
                todo.completedAt = source.completedAt
                todo.order = source.order
                todo.projectOrder = source.projectOrder
                todo.recurrenceSequence = source.recurrenceSequence
                todo.recurrenceTemplate = try importedTemplate(
                    source.recurrenceTemplateID,
                    in: templatesByID
                )
                todo.project = try importedProject(
                    source.projectID,
                    in: projectsByID
                )
            }

            try SwiftDataTransaction.save(context, at: date)
        } catch let error as NagareDataPersistenceError {
            context.rollback()
            throw error
        } catch {
            context.rollback()
            throw NagareDataPersistenceError.saveFailed(
                error.localizedDescription
            )
        }
    }

    func updateNote(
        _ id: NoteRecordID,
        title: String,
        notes: String?,
        at date: Date
    ) throws {
        let context = makeContext()
        do {
            let note: any Note
            switch id {
            case .todo(let id):
                note = try requireTodo(id, in: context)
            case .recurrenceTemplate(let id):
                note = try requireRecurrenceTemplate(id, in: context)
            }
            note.title = title
            note.notes = notes
            try SwiftDataTransaction.save(context, at: date)
        } catch let error as NagareDataPersistenceError {
            throw error
        } catch {
            throw NagareDataPersistenceError.saveFailed(
                error.localizedDescription
            )
        }
    }

    func updateProject(
        _ id: UUID,
        title: String,
        notes: String?,
        at date: Date
    ) throws {
        let context = makeContext()
        do {
            let project = try requireProject(id, in: context)
            project.title = title
            project.notes = notes
            try SwiftDataTransaction.save(context, at: date)
        } catch let error as NagareDataPersistenceError {
            throw error
        } catch {
            throw NagareDataPersistenceError.saveFailed(
                error.localizedDescription
            )
        }
    }

    func saveItemOrdering(
        _ changes: [ItemOrderingChange],
        at date: Date
    ) throws {
        let context = makeContext()
        do {
            try applyItemOrdering(changes, in: context)
            try SwiftDataTransaction.save(context, at: date)
        } catch let error as NagareDataPersistenceError {
            throw error
        } catch {
            throw NagareDataPersistenceError.saveFailed(
                error.localizedDescription
            )
        }
    }

    func saveProjectOrdering(
        _ changes: [ProjectOrderingChange],
        at date: Date
    ) throws {
        let context = makeContext()
        do {
            try applyProjectOrdering(changes, in: context)
            try SwiftDataTransaction.save(context, at: date)
        } catch let error as NagareDataPersistenceError {
            throw error
        } catch {
            throw NagareDataPersistenceError.saveFailed(
                error.localizedDescription
            )
        }
    }

    func saveProjectItemOrdering(
        _ changes: [ProjectItemOrderingChange],
        at date: Date
    ) throws {
        let context = makeContext()
        do {
            try applyProjectItemOrdering(changes, in: context)
            try SwiftDataTransaction.save(context, at: date)
        } catch let error as NagareDataPersistenceError {
            throw error
        } catch {
            throw NagareDataPersistenceError.saveFailed(
                error.localizedDescription
            )
        }
    }

    func deleteProject(_ id: UUID, at date: Date) throws {
        let context = makeContext()
        do {
            let project = try requireProject(id, in: context)
            try ProjectPersistence.delete(project, at: date, in: context)
        } catch let error as NagareDataPersistenceError {
            throw error
        } catch {
            throw NagareDataPersistenceError.saveFailed(
                error.localizedDescription
            )
        }
    }

    func completeTodo(_ id: UUID, at date: Date) throws {
        let context = makeContext()
        do {
            let todo = try requireTodo(id, in: context)
            _ = try RecurrencePersistence.complete(
                todo,
                at: date,
                in: context
            )
        } catch let error as NagareDataPersistenceError {
            throw error
        } catch {
            throw NagareDataPersistenceError.saveFailed(
                error.localizedDescription
            )
        }
    }

    func reinstateTodo(
        _ plan: TodoReinstatementPlan,
        at transactionDate: Date
    ) throws {
        let context = makeContext()
        do {
            try applyItemOrdering(plan.orderRepairs, in: context)
            try applyProjectItemOrdering(
                plan.projectOrderRepairs,
                in: context
            )
            let todo = try requireTodo(plan.id, in: context)
            guard todo.completedAt != nil else {
                throw NagareDataPersistenceError.invalidState(
                    "The Todo is no longer completed."
                )
            }
            todo.recurrenceTemplate = nil
            todo.recurrenceSequence = nil
            todo.move(to: plan.scheduledDate)
            todo.order = plan.order
            todo.projectOrder = plan.projectOrder
            todo.completedAt = nil
            try SwiftDataTransaction.save(context, at: transactionDate)
        } catch let error as NagareDataPersistenceError {
            throw error
        } catch {
            throw NagareDataPersistenceError.saveFailed(
                error.localizedDescription
            )
        }
    }

    func deleteCompletedTodo(_ id: UUID, at date: Date) throws {
        let context = makeContext()
        do {
            let todo = try requireTodo(id, in: context)
            try RecurrencePersistence.deleteCompleted(
                todo,
                at: date,
                in: context
            )
        } catch let error as NagareDataPersistenceError {
            throw error
        } catch {
            throw NagareDataPersistenceError.saveFailed(
                error.localizedDescription
            )
        }
    }

    func deleteItem(_ id: UUID, at date: Date) throws {
        try deleteItems([id], at: date)
    }

    func deleteItems(_ ids: [UUID], at date: Date) throws {
        let context = makeContext()
        do {
            guard Set(ids).count == ids.count else {
                throw NagareDataPersistenceError.saveFailed(
                    "The item selection contains duplicates."
                )
            }
            let todos = try ids.map { try requireTodo($0, in: context) }
            _ = try RecurrencePersistence.delete(
                todos,
                at: date,
                in: context
            )
        } catch let error as NagareDataPersistenceError {
            throw error
        } catch {
            throw NagareDataPersistenceError.saveFailed(
                error.localizedDescription
            )
        }
    }

    func deleteRecurrenceTemplate(_ id: UUID, at date: Date) throws {
        let context = makeContext()
        do {
            let template = try requireRecurrenceTemplate(id, in: context)
            try RecurrencePersistence.deleteTemplate(
                template,
                at: date,
                in: context
            )
        } catch let error as NagareDataPersistenceError {
            throw error
        } catch {
            throw NagareDataPersistenceError.saveFailed(
                error.localizedDescription
            )
        }
    }

    func assign(_ plan: ProjectAssignmentPlan, at date: Date) throws {
        let context = makeContext()
        do {
            try applyProjectItemOrdering(
                plan.projectOrderRepairs,
                in: context
            )
            let project: Project? = try plan.projectID.map {
                try requireProject($0, in: context)
            }
            let item = try requireTodo(plan.itemID, in: context)
            item.project = project
            item.projectOrder = plan.projectOrder
            if let id = plan.recurrenceTemplateID {
                try requireRecurrenceTemplate(id, in: context).project = project
            }
            try SwiftDataTransaction.save(context, at: date)
        } catch let error as NagareDataPersistenceError {
            throw error
        } catch {
            throw NagareDataPersistenceError.saveFailed(
                error.localizedDescription
            )
        }
    }

    func assign(_ plan: ProjectAssignmentBatchPlan, at date: Date) throws {
        let context = makeContext()
        do {
            try applyProjectItemOrdering(
                plan.projectOrderChanges,
                in: context
            )
            let project: Project? = try plan.projectID.map {
                try requireProject($0, in: context)
            }
            for entry in plan.entries {
                let item = try requireTodo(entry.itemID, in: context)
                item.project = project
                item.projectOrder = entry.projectOrder
                if let id = entry.recurrenceTemplateID {
                    try requireRecurrenceTemplate(id, in: context).project = project
                }
            }
            try SwiftDataTransaction.save(context, at: date)
        } catch let error as NagareDataPersistenceError {
            throw error
        } catch {
            context.rollback()
            throw NagareDataPersistenceError.saveFailed(
                error.localizedDescription
            )
        }
    }

    func updateRecurrenceTemplate(
        _ id: UUID,
        rule: RecurrenceRule,
        startTimeSeconds: Int?,
        endTimeSeconds: Int?,
        at date: Date
    ) throws {
        let context = makeContext()
        do {
            let template = try requireRecurrenceTemplate(id, in: context)
            try RecurrencePersistence.updateTemplate(
                template,
                rule: rule,
                startTimeSeconds: startTimeSeconds,
                endTimeSeconds: endTimeSeconds,
                at: date,
                in: context
            )
        } catch let error as NagareDataPersistenceError {
            throw error
        } catch {
            throw NagareDataPersistenceError.saveFailed(
                error.localizedDescription
            )
        }
    }

    private func makeContext() -> ModelContext {
        let context = ModelContext(modelContainer)
        context.autosaveEnabled = false
        context.author = historyAuthor
        return context
    }

    private func applyItemOrdering(
        _ changes: [ItemOrderingChange],
        in context: ModelContext
    ) throws {
        for change in changes {
            let todo = try requireTodo(change.id, in: context)
            if let order = change.order { todo.order = order }
            if let scheduledDate = change.scheduledDate {
                todo.scheduledDate = scheduledDate
                if let includesTime = change.includesTime {
                    todo.includesTime = includesTime
                }
                todo.endDate = todo.includesTime ? change.endDate : nil
                if todo.recurrenceTemplate != nil, todo.includesTime {
                    _ = try RecurrenceTransitionLogic.wallTimes(
                        scheduledDate: scheduledDate,
                        endDate: todo.endDate,
                        calendar: .autoupdatingCurrent
                    )
                }
            }
        }
    }

    private func applyProjectOrdering(
        _ changes: [ProjectOrderingChange],
        in context: ModelContext
    ) throws {
        for change in changes {
            let project = try requireProject(change.id, in: context)
            if let order = change.order { project.order = order }
            if let priority = change.priority {
                project.priority = priority
            }
        }
    }

    private func applyProjectItemOrdering(
        _ changes: [ProjectItemOrderingChange],
        in context: ModelContext
    ) throws {
        for change in changes {
            try requireTodo(change.id, in: context).projectOrder =
                change.projectOrder
        }
    }

    private func create(
        _ draft: ItemDraft,
        order: String,
        projectOrder: String?,
        at date: Date,
        in context: ModelContext
    ) -> Todo {
        let todo = Todo(
            title: draft.title,
            notes: draft.notes,
            scheduledDate: draft.scheduledDate,
            includesTime: draft.includesTime,
            endDate: draft.endDate,
            createdAt: date,
            order: order,
            projectOrder: projectOrder
        )
        // The use case already canonicalized this instant with its explicit
        // calendar; do not reinterpret it using the repository's time zone.
        todo.scheduledDate = draft.scheduledDate
        context.insert(todo)
        return todo
    }

    private func apply(_ draft: ItemDraft, to todo: Todo) {
        todo.title = draft.title
        todo.notes = draft.notes
        todo.scheduledDate = draft.scheduledDate
        todo.includesTime = draft.includesTime
        todo.endDate = draft.includesTime ? draft.endDate : nil
    }

    private func applyProject(
        to todo: Todo,
        projectID: UUID?,
        projectOrder: String?,
        in context: ModelContext
    ) throws {
        let project: Project? = try projectID.map {
            try requireProject($0, in: context)
        }
        todo.project = project
        todo.projectOrder = projectOrder
        todo.recurrenceTemplate?.project = project
    }

    private func persistRecurrence(
        for todo: Todo,
        draft: ItemDraft,
        at date: Date,
        in context: ModelContext
    ) throws {
        if let template = todo.recurrenceTemplate {
            template.title = draft.title
            template.notes = draft.notes
            if let rule = draft.recurrenceRule {
                try RecurrencePersistence.updateTemplate(
                    template,
                    rule: rule,
                    startTimeSeconds: draft.startTimeSeconds,
                    endTimeSeconds: draft.endTimeSeconds,
                    at: date,
                    in: context
                )
            } else {
                try RecurrencePersistence.deleteTemplate(
                    template,
                    at: date,
                    in: context
                )
            }
        } else if let rule = draft.recurrenceRule {
            _ = try RecurrencePersistence.createTemplate(
                for: todo,
                rule: rule,
                at: date,
                in: context
            )
        } else {
            try SwiftDataTransaction.save(context, at: date)
        }
    }

    private func currentScheduledDate(
        for template: RecurrenceTemplate
    ) -> Date? {
        template.todoOccurrences.first {
            $0.id == template.currentItemID && $0.completedAt == nil
        }?.scheduledDate
    }

    private func requireTodo(
        _ id: UUID,
        in context: ModelContext
    ) throws -> Todo {
        let records = try context.fetch(
            FetchDescriptor<Todo>(
                predicate: #Predicate<Todo> { $0.id == id }
            )
        )
        return try requireExactlyOne(records, id: id)
    }

    private func requireProject(
        _ id: UUID,
        in context: ModelContext
    ) throws -> Project {
        let records = try context.fetch(
            FetchDescriptor<Project>(
                predicate: #Predicate<Project> { $0.id == id }
            )
        )
        return try requireExactlyOne(records, id: id)
    }

    private func requireRecurrenceTemplate(
        _ id: UUID,
        in context: ModelContext
    ) throws -> RecurrenceTemplate {
        let records = try context.fetch(
            FetchDescriptor<RecurrenceTemplate>(
                predicate: #Predicate<RecurrenceTemplate> { $0.id == id }
            )
        )
        return try requireExactlyOne(records, id: id)
    }

    private func requireExactlyOne<Record>(
        _ records: [Record],
        id: UUID
    ) throws -> Record {
        guard records.count == 1, let record = records.first else {
            throw NagareDataPersistenceError.invalidIdentity(
                id,
                count: records.count
            )
        }
        return record
    }

    private func existingRecord<Record>(
        _ id: UUID,
        in recordsByID: [UUID: [Record]]
    ) throws -> Record? {
        let records = recordsByID[id] ?? []
        guard records.count <= 1 else {
            throw NagareDataPersistenceError.invalidIdentity(
                id,
                count: records.count
            )
        }
        return records.first
    }

    private func importedProject(
        _ id: UUID?,
        in projectsByID: [UUID: Project]
    ) throws -> Project? {
        guard let id else { return nil }
        guard let project = projectsByID[id] else {
            throw NagareDataPersistenceError.invalidState(
                "The imported project \(id.uuidString) wasn't available."
            )
        }
        return project
    }

    private func importedTemplate(
        _ id: UUID?,
        in templatesByID: [UUID: RecurrenceTemplate]
    ) throws -> RecurrenceTemplate? {
        guard let id else { return nil }
        guard let template = templatesByID[id] else {
            throw NagareDataPersistenceError.invalidState(
                "The imported recurrence \(id.uuidString) wasn't available."
            )
        }
        return template
    }
}

nonisolated enum NagareDataPersistenceError: Error, LocalizedError {
    case loadFailed(String)
    case saveFailed(String)
    case invalidIdentity(UUID, count: Int)
    case invalidState(String)

    var errorDescription: String? {
        switch self {
        case .loadFailed(let message):
            "Nagare couldn't read its data. \(message)"
        case .saveFailed(let message):
            "Nagare couldn't save that change. \(message)"
        case .invalidIdentity(let id, let count):
            "Nagare found \(count) records for \(id.uuidString); expected exactly one."
        case .invalidState(let message):
            "Nagare refused a stale change. \(message)"
        }
    }
}
