import Foundation
import SwiftData

@MainActor
enum RecurrencePersistence {
    static func createTemplate(
        for todo: Todo,
        rule: RecurrenceRule,
        at modificationDate: Date = .now,
        in context: ModelContext,
        calendar: Calendar = .autoupdatingCurrent
    ) throws -> RecurrenceTemplate {
        try perform(in: context, at: modificationDate) {
            guard todo.recurrenceTemplate == nil,
                  todo.recurrenceSequence == nil else {
                throw RecurrencePersistenceError.itemAlreadyRepeats
            }
            guard todo.completedAt == nil else {
                throw RecurrencePersistenceError.todoAlreadyCompleted
            }
            try validate(order: todo.order)
            let times = try recurrenceTimes(for: todo, calendar: calendar)
            let template = RecurrenceTemplate(
                title: todo.title,
                notes: todo.notes,
                rule: rule,
                startTimeSeconds: times.start,
                endTimeSeconds: times.end,
                currentItemID: todo.id,
                createdAt: modificationDate
            )
            context.insert(template)
            template.project = todo.project
            todo.recurrenceSequence = 0
            todo.recurrenceTemplate = template
            return template
        }
    }

    static func updateTemplate(
        _ template: RecurrenceTemplate,
        rule: RecurrenceRule,
        startTimeSeconds: Int? = nil,
        endTimeSeconds: Int? = nil,
        at modificationDate: Date = .now,
        in context: ModelContext
    ) throws {
        try perform(in: context, at: modificationDate) {
            try validateTimes(
                startTimeSeconds: startTimeSeconds,
                endTimeSeconds: endTimeSeconds
            )
            template.startTimeSeconds = startTimeSeconds
            template.endTimeSeconds = endTimeSeconds
            template.modeRawValue = rule.mode.rawValue
            template.unitRawValue = rule.unit.rawValue
            template.interval = rule.interval
            template.anchors = rule.anchors
            template.reference = rule.reference
            template.repeatUntil = rule.repeatUntil
        }
    }

    /// Marks a Todo complete and, when it repeats, creates exactly one new
    /// current occurrence from the template. The completed Todo is retained.
    @discardableResult
    static func complete(
        _ todo: Todo,
        at completionDate: Date = .now,
        in context: ModelContext,
        calendar: Calendar = .autoupdatingCurrent
    ) throws -> Todo? {
        try perform(in: context, at: completionDate) {
            guard todo.completedAt == nil else {
                throw RecurrencePersistenceError.todoAlreadyCompleted
            }
            guard let template = todo.recurrenceTemplate else {
                todo.completedAt = completionDate
                return nil
            }

            try validateCurrent(todo, for: template)
            let next = try makeNextTodo(
                after: todo,
                from: template,
                createdAt: completionDate,
                calendar: calendar
            )
            todo.completedAt = completionDate
            guard let next else {
                terminate(template, in: context)
                return nil
            }
            context.insert(next)
            next.recurrenceTemplate = template
            guard let nextSequence = next.recurrenceSequence else {
                throw RecurrencePersistenceError.sequenceMismatch
            }
            template.currentItemID = next.id
            template.currentSequence = nextSequence
            return next
        }
    }

    /// Returns a completed Todo to Today while preserving its optional time.
    /// Completed recurring occurrences are detached from the active series.
    static func reinstate(
        _ todo: Todo,
        on date: Date = .now,
        at modificationDate: Date = .now,
        in context: ModelContext,
        calendar: Calendar = .autoupdatingCurrent
    ) throws {
        try perform(in: context, at: modificationDate) {
            guard todo.completedAt != nil else {
                throw RecurrencePersistenceError.todoNotCompleted
            }
            let order = try ItemOrdering.nextOrder(in: context)
            let projectOrder = try todo.project.map {
                try ProjectItemOrdering.nextOrder(in: $0, context: context)
            }
            todo.recurrenceTemplate = nil
            todo.recurrenceSequence = nil
            todo.move(to: date, calendar: calendar)
            todo.order = order
            todo.projectOrder = projectOrder
            todo.completedAt = nil
        }
    }

    static func deleteCompleted(
        _ todo: Todo,
        at modificationDate: Date = .now,
        in context: ModelContext
    ) throws {
        try perform(in: context, at: modificationDate) {
            try prepareCompletedDeletion(todo, in: context)
        }
    }

    @discardableResult
    static func delete(
        _ todo: Todo,
        at transitionDate: Date = .now,
        in context: ModelContext,
        calendar: Calendar = .autoupdatingCurrent
    ) throws -> Todo? {
        try perform(in: context, at: transitionDate) {
            try prepareDeletion(
                todo,
                at: transitionDate,
                in: context,
                calendar: calendar
            )
        }
    }

    static func delete(
        _ todos: [Todo],
        at transitionDate: Date = .now,
        in context: ModelContext,
        calendar: Calendar = .autoupdatingCurrent
    ) throws -> [Todo?] {
        try perform(in: context, at: transitionDate) {
            guard Set(todos.map(\.id)).count == todos.count else {
                throw RecurrencePersistenceError.duplicateItems
            }
            return try todos.map { todo in
                if todo.completedAt != nil {
                    try prepareCompletedDeletion(todo, in: context)
                    return nil
                }
                return try prepareDeletion(
                    todo,
                    at: transitionDate,
                    in: context,
                    calendar: calendar
                )
            }
        }
    }

    /// Stops future recurrence while retaining the current occurrence as a
    /// normal Todo. Completed occurrence history remains persisted.
    static func deleteTemplate(
        _ template: RecurrenceTemplate,
        at modificationDate: Date = .now,
        in context: ModelContext
    ) throws {
        try perform(in: context, at: modificationDate) {
            for todo in template.todoOccurrences {
                todo.recurrenceTemplate = nil
                todo.recurrenceSequence = nil
            }
            context.delete(template)
        }
    }

    private static func makeNextTodo(
        after current: Todo,
        from template: RecurrenceTemplate,
        createdAt: Date,
        calendar: Calendar
    ) throws -> Todo? {
        let draft: TodoOccurrenceDraft?
        do {
            draft = try RecurrenceTransitionLogic.nextTodo(
                after: RecurrenceOccurrenceSnapshot(
                    scheduledDate: current.scheduledDate,
                    order: current.order,
                    projectOrder: current.projectOrder
                ),
                from: try transitionSnapshot(template, calendar: calendar),
                createdAt: createdAt,
                calendar: calendar
            )
        } catch let error as RecurrenceTransitionLogic.TransitionError {
            throw persistenceError(for: error)
        }
        guard let draft else { return nil }
        let next = Todo(
            title: draft.title,
            notes: draft.notes,
            scheduledDate: draft.scheduledDate,
            includesTime: draft.includesTime,
            endDate: draft.endDate,
            createdAt: draft.createdAt,
            order: draft.order,
            projectOrder: draft.projectOrder,
            calendar: calendar
        )
        // Draft dates are already canonicalized with the transaction calendar.
        next.scheduledDate = draft.scheduledDate
        next.project = template.project
        next.recurrenceSequence = draft.sequence
        return next
    }

    private static func prepareCompletedDeletion(
        _ todo: Todo,
        in context: ModelContext
    ) throws {
        guard todo.completedAt != nil else {
            throw RecurrencePersistenceError.todoNotCompleted
        }
        context.delete(todo)
    }

    private static func prepareDeletion(
        _ todo: Todo,
        at transitionDate: Date,
        in context: ModelContext,
        calendar: Calendar
    ) throws -> Todo? {
        guard let template = todo.recurrenceTemplate else {
            context.delete(todo)
            return nil
        }
        try validateCurrent(todo, for: template)
        let next = try makeNextTodo(
            after: todo,
            from: template,
            createdAt: transitionDate,
            calendar: calendar
        )
        guard let next else {
            terminate(template, in: context)
            context.delete(todo)
            return nil
        }
        context.insert(next)
        next.recurrenceTemplate = template
        guard let nextSequence = next.recurrenceSequence else {
            throw RecurrencePersistenceError.sequenceMismatch
        }
        template.currentItemID = next.id
        template.currentSequence = nextSequence
        context.delete(todo)
        return next
    }

    private static func terminate(
        _ template: RecurrenceTemplate,
        in context: ModelContext
    ) {
        for occurrence in template.todoOccurrences {
            occurrence.recurrenceTemplate = nil
            occurrence.recurrenceSequence = nil
        }
        context.delete(template)
    }

    private static func validateCurrent(
        _ todo: Todo,
        for template: RecurrenceTemplate
    ) throws {
        guard template.currentItemID == todo.id else {
            throw RecurrencePersistenceError.itemIsNotCurrent
        }
        guard todo.recurrenceSequence == template.currentSequence else {
            throw RecurrencePersistenceError.sequenceMismatch
        }
        let activeOccurrences = template.todoOccurrences.filter {
            $0.completedAt == nil
        }
        guard activeOccurrences.count == 1,
              activeOccurrences.first?.id == todo.id else {
            throw RecurrencePersistenceError.invalidCurrentOccurrences
        }
        try validate(order: todo.order)
    }

    private static func recurrenceTimes(
        for todo: Todo,
        calendar: Calendar
    ) throws -> (start: Int?, end: Int?) {
        guard todo.includesTime else { return (nil, nil) }
        do {
            let times = try RecurrenceTransitionLogic.wallTimes(
                scheduledDate: todo.scheduledDate,
                endDate: todo.endDate,
                calendar: calendar
            )
            return (times.start, times.end)
        } catch let error as RecurrenceTransitionLogic.TransitionError {
            throw persistenceError(for: error)
        }
    }

    private static func validateTimes(
        startTimeSeconds: Int?,
        endTimeSeconds: Int?
    ) throws {
        guard let startTimeSeconds else {
            guard endTimeSeconds == nil else {
                throw RecurrencePersistenceError.invalidTime
            }
            return
        }
        guard (0..<86_400).contains(startTimeSeconds) else {
            throw RecurrencePersistenceError.invalidTime
        }
        if let endTimeSeconds {
            guard (0..<86_400).contains(endTimeSeconds) else {
                throw RecurrencePersistenceError.invalidTime
            }
        }
    }

    private static func transitionSnapshot(
        _ template: RecurrenceTemplate,
        calendar: Calendar
    ) throws -> RecurrenceTransitionTemplate {
        RecurrenceTransitionTemplate(
            title: template.title,
            notes: template.notes,
            rule: try template.rule(calendar: calendar),
            startTimeSeconds: template.startTimeSeconds,
            endTimeSeconds: template.endTimeSeconds,
            currentSequence: template.currentSequence
        )
    }

    private static func persistenceError(
        for error: RecurrenceTransitionLogic.TransitionError
    ) -> RecurrencePersistenceError {
        switch error {
        case .timeCalculationFailed:
            .timeCalculationFailed
        case .sequenceOverflow:
            .sequenceOverflow
        case .crossesDateBoundary:
            .crossesDateBoundary
        case .invalidTime:
            .invalidTime
        }
    }

    private static func validate(order: String) throws {
        guard FractionalIndex.isValid(order) else {
            throw RecurrencePersistenceError.invalidOrder
        }
    }

    private static func perform<Result>(
        in context: ModelContext,
        at modificationDate: Date,
        _ changes: () throws -> Result
    ) throws -> Result {
        do {
            let result = try changes()
            try SwiftDataTransaction.save(context, at: modificationDate)
            return result
        } catch {
            context.rollback()
            switch error {
            case let recurrenceError as RecurrenceError:
                throw recurrenceError
            case let persistenceError as RecurrencePersistenceError:
                throw persistenceError
            default:
                throw RecurrencePersistenceError.persistenceFailed(
                    error.localizedDescription
                )
            }
        }
    }
}

enum RecurrencePersistenceError: Error, LocalizedError {
    case itemAlreadyRepeats
    case itemIsNotCurrent
    case sequenceMismatch
    case todoAlreadyCompleted
    case todoNotCompleted
    case invalidCurrentOccurrences
    case invalidStoredMode(String)
    case invalidStoredUnit(String)
    case timeCalculationFailed
    case sequenceOverflow
    case invalidOrder
    case invalidTime
    case crossesDateBoundary
    case persistenceFailed(String)
    case duplicateItems

    var code: String {
        switch self {
        case .itemAlreadyRepeats: "RECURRENCE-PERSIST-001"
        case .itemIsNotCurrent: "RECURRENCE-PERSIST-002"
        case .sequenceMismatch: "RECURRENCE-PERSIST-003"
        case .todoAlreadyCompleted: "RECURRENCE-PERSIST-004"
        case .todoNotCompleted: "RECURRENCE-PERSIST-005"
        case .invalidCurrentOccurrences: "RECURRENCE-PERSIST-006"
        case .invalidStoredMode: "RECURRENCE-PERSIST-007"
        case .invalidStoredUnit: "RECURRENCE-PERSIST-008"
        case .timeCalculationFailed: "RECURRENCE-PERSIST-009"
        case .sequenceOverflow: "RECURRENCE-PERSIST-010"
        case .invalidOrder: "RECURRENCE-PERSIST-011"
        case .invalidTime: "RECURRENCE-PERSIST-012"
        case .crossesDateBoundary: "RECURRENCE-PERSIST-013"
        case .persistenceFailed: "RECURRENCE-PERSIST-015"
        case .duplicateItems: "RECURRENCE-PERSIST-016"
        }
    }

    var errorDescription: String? {
        switch self {
        case .itemAlreadyRepeats:
            "This Todo already belongs to a recurrence template. (\(code))"
        case .itemIsNotCurrent:
            "Nagare refused to advance an occurrence that is no longer current. (\(code))"
        case .sequenceMismatch:
            "The occurrence sequence does not match its recurrence template. (\(code))"
        case .todoAlreadyCompleted:
            "Nagare refused to complete the same Todo occurrence twice. (\(code))"
        case .todoNotCompleted:
            "Nagare couldn't modify a Todo that is not completed. (\(code))"
        case .invalidCurrentOccurrences:
            "The recurrence template does not have exactly one current occurrence. (\(code))"
        case .invalidStoredMode(let mode):
            "The recurrence template contains an unknown mode “\(mode)”. (\(code))"
        case .invalidStoredUnit(let unit):
            "The recurrence template contains an unknown unit “\(unit)”. (\(code))"
        case .timeCalculationFailed:
            "Nagare couldn't apply the Todo time to its next date. (\(code))"
        case .sequenceOverflow:
            "The recurrence occurrence counter cannot advance further. (\(code))"
        case .invalidOrder:
            "The current occurrence has an invalid saved position. (\(code))"
        case .invalidTime:
            "A repeating Todo has an invalid time. (\(code))"
        case .crossesDateBoundary:
            "Repeating Todos must start and end on the same day. (\(code))"
        case .persistenceFailed(let message):
            "Nagare couldn't save the recurrence transition. \(message) (\(code))"
        case .duplicateItems:
            "Nagare received the same Todo more than once and left every selected Todo unchanged. (\(code))"
        }
    }
}
