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

    init(modelContainer: ModelContainer) {
        self.modelContainer = modelContainer
    }

    func upsertItem(
        _ plan: ItemUpsertPlan,
        at date: Date
    ) throws -> ItemID {
        let context = makeContext()
        do {
            try applyItemOrdering(plan.orderRepairs, in: context)
            try applyProjectItemOrdering(
                plan.projectOrderRepairs,
                in: context
            )
            let draft = plan.draft
            let item: SwiftDataItem
            if let existingID = plan.existingID {
                let existing = try loadItem(for: existingID, in: context)
                if existing.kind == draft.kind {
                    apply(draft, to: existing)
                    item = existing
                } else {
                    item = replace(
                        existing,
                        with: draft,
                        order: plan.order,
                        projectOrder: plan.projectOrder,
                        in: context
                    )
                }
            } else {
                item = create(
                    draft,
                    order: plan.order,
                    projectOrder: plan.projectOrder,
                    at: date,
                    in: context
                )
            }
            item.applyOrder(plan.order)
            try applyProject(
                to: item,
                projectID: draft.projectID,
                projectOrder: plan.projectOrder,
                in: context
            )
            try persistRecurrence(
                for: item,
                draft: draft,
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
                isPriority: false,
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
                        isPriority: $0.isPriority,
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
                        completedAt: $0.completedAt,
                        order: $0.order,
                        projectOrder: $0.projectOrder,
                        recurrenceSequence: $0.recurrenceSequence,
                        recurrenceTemplateID: $0.recurrenceTemplate?.id,
                        projectID: $0.project?.id
                    )
                },
                events: try context.fetch(FetchDescriptor<Event>()).map {
                    EventRecordSnapshot(
                        id: $0.id,
                        syncRecordID: $0.syncRecordID,
                        createdAt: $0.createdAt,
                        modifiedAt: $0.modifiedAt,
                        title: $0.title,
                        notes: $0.notes,
                        scheduledDate: $0.scheduledDate,
                        endDate: $0.endDate,
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
                        itemTypeRawValue: $0.itemTypeRawValue,
                        title: $0.title,
                        notes: $0.notes,
                        modeRawValue: $0.modeRawValue,
                        unitRawValue: $0.unitRawValue,
                        interval: $0.interval,
                        anchors: $0.anchors,
                        reference: $0.reference,
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
            case .event(let id):
                note = try requireEvent(id, in: context)
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
            todo.scheduledDate = plan.scheduledDate
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

    func deletePastEvents(
        before date: Date,
        at transactionDate: Date
    ) throws {
        let context = makeContext()
        do {
            let descriptor = FetchDescriptor<Event>(
                predicate: #Predicate { event in
                    event.scheduledDate < date
                }
            )
            let events = try context.fetch(descriptor)
            try RecurrencePersistence.removePastEventOccurrences(
                events,
                before: date,
                at: transactionDate,
                in: context
            )
        } catch let error as NagareDataPersistenceError {
            throw error
        } catch {
            context.rollback()
            throw NagareDataPersistenceError.saveFailed(
                error.localizedDescription
            )
        }
    }

    func deleteItem(_ id: ItemID, at date: Date) throws {
        try deleteItems([id], at: date)
    }

    func deleteItems(_ ids: [ItemID], at date: Date) throws {
        let context = makeContext()
        do {
            guard Set(ids).count == ids.count else {
                throw NagareDataPersistenceError.saveFailed(
                    "The item selection contains duplicates."
                )
            }
            var todos: [Todo] = []
            var events: [Event] = []
            for id in ids {
                switch id {
                case .todo(let id):
                    todos.append(try requireTodo(id, in: context))
                case .event(let id):
                    events.append(try requireEvent(id, in: context))
                }
            }
            try RecurrencePersistence.delete(
                todos: todos,
                events: events,
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
            let item = try loadItem(for: plan.itemID, in: context)
            item.applyProject(project)
            item.applyProjectOrder(plan.projectOrder)
            if let id = plan.recurrenceTemplateID {
                let template = try requireRecurrenceTemplate(
                    id,
                    in: context
                )
                template.project = project
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
                let item = try loadItem(for: entry.itemID, in: context)
                item.applyProject(project)
                item.applyProjectOrder(entry.projectOrder)
                if let id = entry.recurrenceTemplateID {
                    let template = try requireRecurrenceTemplate(
                        id,
                        in: context
                    )
                    template.project = project
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
        eventStartTimeSeconds: Int?,
        eventEndTimeSeconds: Int?,
        at date: Date
    ) throws {
        let context = makeContext()
        do {
            let template = try requireRecurrenceTemplate(id, in: context)
            try RecurrencePersistence.updateTemplate(
                template,
                rule: rule,
                eventStartTimeSeconds: eventStartTimeSeconds,
                eventEndTimeSeconds: eventEndTimeSeconds,
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
        context.author = NagareCloud.localHistoryAuthor
        return context
    }

    private func applyItemOrdering(
        _ changes: [ItemOrderingChange],
        in context: ModelContext
    ) throws {
        for change in changes {
            switch change.id {
            case .todo(let id):
                let todo = try requireTodo(id, in: context)
                if let order = change.order { todo.order = order }
                if let scheduledDate = change.scheduledDate {
                    todo.scheduledDate = scheduledDate
                }
            case .event(let id):
                let event = try requireEvent(id, in: context)
                if let order = change.order { event.order = order }
                if let scheduledDate = change.scheduledDate {
                    event.scheduledDate = scheduledDate
                    event.endDate = change.endDate
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
            if let isPriority = change.isPriority {
                project.isPriority = isPriority
            }
        }
    }

    private func applyProjectItemOrdering(
        _ changes: [ProjectItemOrderingChange],
        in context: ModelContext
    ) throws {
        for change in changes {
            switch change.id {
            case .todo(let id):
                let todo = try requireTodo(id, in: context)
                todo.projectOrder = change.projectOrder
            case .event(let id):
                let event = try requireEvent(id, in: context)
                event.projectOrder = change.projectOrder
            }
        }
    }

    private func loadItem(
        for id: ItemID,
        in context: ModelContext
    ) throws -> SwiftDataItem {
        switch id {
        case .todo(let id):
            .todo(try requireTodo(id, in: context))
        case .event(let id):
            .event(try requireEvent(id, in: context))
        }
    }

    private func create(
        _ draft: ItemDraft,
        order: String,
        projectOrder: String?,
        at date: Date,
        in context: ModelContext
    ) -> SwiftDataItem {
        switch draft.kind {
        case .todo:
            let todo = Todo(
                title: draft.title,
                notes: draft.notes,
                scheduledDate: draft.scheduledDate,
                createdAt: date,
                order: order,
                projectOrder: projectOrder
            )
            // ItemDraft dates are already canonicalized by the use case's
            // explicit calendar. Do not reinterpret that instant using this
            // device's current time zone.
            todo.scheduledDate = draft.scheduledDate
            context.insert(todo)
            return SwiftDataItem.todo(todo)
        case .event:
            let event = Event(
                title: draft.title,
                notes: draft.notes,
                scheduledDate: draft.scheduledDate,
                endDate: draft.endDate,
                createdAt: date,
                order: order,
                projectOrder: projectOrder
            )
            context.insert(event)
            return SwiftDataItem.event(event)
        }
    }

    private func apply(
        _ draft: ItemDraft,
        to item: SwiftDataItem
    ) {
        switch item {
        case .todo(let todo):
            todo.title = draft.title
            todo.notes = draft.notes
            todo.scheduledDate = draft.scheduledDate
        case .event(let event):
            event.title = draft.title
            event.notes = draft.notes
            event.scheduledDate = draft.scheduledDate
            event.endDate = draft.endDate
        }
    }

    private func replace(
        _ item: SwiftDataItem,
        with draft: ItemDraft,
        order: String,
        projectOrder: String?,
        in context: ModelContext
    ) -> SwiftDataItem {
        let createdAt = item.createdAt
        switch item {
        case .todo(let todo):
            if let template = todo.recurrenceTemplate {
                context.delete(template)
            }
            context.delete(todo)
        case .event(let event):
            if let template = event.recurrenceTemplate {
                context.delete(template)
            }
            context.delete(event)
        }

        let replacement: SwiftDataItem
        switch draft.kind {
        case .todo:
            let todo = Todo(
                title: draft.title,
                notes: draft.notes,
                scheduledDate: draft.scheduledDate,
                createdAt: createdAt,
                order: order,
                projectOrder: projectOrder
            )
            todo.scheduledDate = draft.scheduledDate
            context.insert(todo)
            replacement = .todo(todo)
        case .event:
            let event = Event(
                title: draft.title,
                notes: draft.notes,
                scheduledDate: draft.scheduledDate,
                endDate: draft.endDate,
                createdAt: createdAt,
                order: order,
                projectOrder: projectOrder
            )
            context.insert(event)
            replacement = .event(event)
        }
        return replacement
    }

    private func applyProject(
        to item: SwiftDataItem,
        projectID: UUID?,
        projectOrder: String?,
        in context: ModelContext
    ) throws {
        let project: Project? = try projectID.map {
            try requireProject($0, in: context)
        }
        item.applyProject(project)
        item.applyProjectOrder(projectOrder)
        switch item {
        case .todo(let todo):
            todo.recurrenceTemplate?.project = project
        case .event(let event):
            event.recurrenceTemplate?.project = project
        }
    }

    private func persistRecurrence(
        for item: SwiftDataItem,
        draft: ItemDraft,
        at date: Date,
        in context: ModelContext
    ) throws {
        switch item {
        case .todo(let todo):
            if let template = todo.recurrenceTemplate {
                template.title = draft.title
                template.notes = draft.notes
                if let rule = draft.recurrenceRule {
                    try RecurrencePersistence.updateTemplate(
                        template,
                        rule: rule,
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
        case .event(let event):
            if let template = event.recurrenceTemplate {
                template.title = draft.title
                template.notes = draft.notes
                if let rule = draft.recurrenceRule {
                    try RecurrencePersistence.updateTemplate(
                        template,
                        rule: rule,
                        eventStartTimeSeconds: draft.eventStartTimeSeconds,
                        eventEndTimeSeconds: draft.eventEndTimeSeconds,
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
                    for: event,
                    rule: rule,
                    at: date,
                    in: context
                )
            } else {
                try SwiftDataTransaction.save(context, at: date)
            }
        }
    }

    private func currentScheduledDate(
        for template: RecurrenceTemplate
    ) -> Date? {
        switch template.itemType {
        case .todo:
            template.todoOccurrences.first {
                $0.id == template.currentItemID && $0.completedAt == nil
            }?.scheduledDate
        case .event:
            template.eventOccurrences.first {
                $0.id == template.currentItemID
            }?.scheduledDate
        case nil:
            nil
        }
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

    private func requireEvent(
        _ id: UUID,
        in context: ModelContext
    ) throws -> Event {
        let records = try context.fetch(
            FetchDescriptor<Event>(
                predicate: #Predicate<Event> { $0.id == id }
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
