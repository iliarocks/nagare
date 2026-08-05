import Foundation
import SwiftData

@MainActor
enum RecurrencePersistence {
    static func createTemplate(
        for todo: Todo,
        rule: RecurrenceRule,
        in context: ModelContext
    ) throws -> RecurrenceTemplate {
        try perform(in: context) {
            guard todo.recurrenceTemplate == nil,
                  todo.recurrenceSequence == nil else {
                throw RecurrencePersistenceError.itemAlreadyRepeats
            }
            guard todo.completedAt == nil else {
                throw RecurrencePersistenceError.todoAlreadyCompleted
            }
            try validate(order: todo.order)

            let template = RecurrenceTemplate(
                itemType: .todo,
                title: todo.title,
                notes: todo.notes,
                rule: rule,
                currentItemID: todo.id
            )
            context.insert(template)
            template.project = todo.project
            todo.recurrenceSequence = 0
            todo.recurrenceTemplate = template
            return template
        }
    }

    static func createTemplate(
        for event: Event,
        rule: RecurrenceRule,
        in context: ModelContext,
        calendar: Calendar = .autoupdatingCurrent
    ) throws -> RecurrenceTemplate {
        try perform(in: context) {
            guard event.recurrenceTemplate == nil,
                  event.recurrenceSequence == nil else {
                throw RecurrencePersistenceError.itemAlreadyRepeats
            }
            guard rule.mode == .absolute else {
                throw RecurrencePersistenceError.relativeEventUnsupported
            }
            try validate(order: event.order)

            let times = try eventTimes(for: event, calendar: calendar)
            let template = RecurrenceTemplate(
                itemType: .event,
                title: event.title,
                notes: event.notes,
                rule: rule,
                startTimeSeconds: times.start,
                endTimeSeconds: times.end,
                currentItemID: event.id
            )
            context.insert(template)
            template.project = event.project
            event.recurrenceSequence = 0
            event.recurrenceTemplate = template
            return template
        }
    }

    static func updateTemplate(
        _ template: RecurrenceTemplate,
        rule: RecurrenceRule,
        eventStartTimeSeconds: Int? = nil,
        eventEndTimeSeconds: Int? = nil,
        in context: ModelContext
    ) throws {
        try perform(in: context) {
            guard let itemType = template.itemType else {
                throw RecurrencePersistenceError.wrongItemType
            }

            switch itemType {
            case .todo:
                template.startTimeSeconds = nil
                template.endTimeSeconds = nil
            case .event:
                guard rule.mode == .absolute else {
                    throw RecurrencePersistenceError.relativeEventUnsupported
                }
                guard let eventStartTimeSeconds,
                      (0..<86_400).contains(eventStartTimeSeconds) else {
                    throw RecurrencePersistenceError.invalidEventTime
                }
                if let eventEndTimeSeconds {
                    guard (0..<86_400).contains(eventEndTimeSeconds) else {
                        throw RecurrencePersistenceError.invalidEventTime
                    }
                    guard eventEndTimeSeconds >= eventStartTimeSeconds else {
                        throw RecurrencePersistenceError.eventEndsBeforeItStarts
                    }
                }
                template.startTimeSeconds = eventStartTimeSeconds
                template.endTimeSeconds = eventEndTimeSeconds
            }

            template.modeRawValue = rule.mode.rawValue
            template.unitRawValue = rule.unit.rawValue
            template.interval = rule.interval
            template.anchors = rule.anchors
            template.reference = rule.reference
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
        try perform(in: context) {
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

    /// Returns a completed Todo to Today as the final item in the list.
    /// Completed recurring occurrences are detached so the recurrence's
    /// already-created current occurrence remains unchanged.
    static func reinstate(
        _ todo: Todo,
        on date: Date = .now,
        in context: ModelContext,
        calendar: Calendar = .autoupdatingCurrent
    ) throws {
        try perform(in: context) {
            guard todo.completedAt != nil else {
                throw RecurrencePersistenceError.todoNotCompleted
            }

            let order = try ItemOrdering.nextOrder(in: context)
            let projectOrder = try todo.project.map {
                try ProjectItemOrdering.nextOrder(in: $0, context: context)
            }
            todo.recurrenceTemplate = nil
            todo.recurrenceSequence = nil
            todo.scheduledDate = calendar.startOfDay(for: date)
            todo.order = order
            todo.projectOrder = projectOrder
            todo.completedAt = nil
        }
    }

    /// Permanently removes one completed Todo occurrence. Deleting completed
    /// recurrence history does not affect the template's current occurrence.
    static func deleteCompleted(
        _ todo: Todo,
        in context: ModelContext
    ) throws {
        try perform(in: context) {
            guard todo.completedAt != nil else {
                throw RecurrencePersistenceError.todoNotCompleted
            }

            context.delete(todo)
        }
    }

    /// Deletes the current Todo occurrence without marking it complete, then
    /// creates the next occurrence when the Todo repeats.
    @discardableResult
    static func delete(
        _ todo: Todo,
        at transitionDate: Date = .now,
        in context: ModelContext,
        calendar: Calendar = .autoupdatingCurrent
    ) throws -> Todo? {
        try perform(in: context) {
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
    }

    /// Deletes an Event occurrence and advances its template to a newly
    /// persisted current Event. Non-repeating Events are simply deleted.
    @discardableResult
    static func delete(
        _ event: Event,
        at transitionDate: Date = .now,
        in context: ModelContext,
        calendar: Calendar = .autoupdatingCurrent
    ) throws -> Event? {
        try perform(in: context) {
            guard let template = event.recurrenceTemplate else {
                context.delete(event)
                return nil
            }

            try validateCurrent(event, for: template)
            let next = try makeNextEvent(
                after: event,
                from: template,
                createdAt: transitionDate,
                calendar: calendar
            )

            context.insert(next)
            next.recurrenceTemplate = template
            guard let nextSequence = next.recurrenceSequence else {
                throw RecurrencePersistenceError.sequenceMismatch
            }
            template.currentItemID = next.id
            template.currentSequence = nextSequence
            context.delete(event)
            return next
        }
    }

    /// Deletes the current Event together with its recurrence template. Since
    /// Nagare persists only the current Event occurrence, this removes this
    /// and every future occurrence represented by the series.
    static func deleteSeries(
        containing event: Event,
        in context: ModelContext
    ) throws {
        try perform(in: context) {
            guard let template = event.recurrenceTemplate else {
                context.delete(event)
                return
            }

            try validateCurrent(event, for: template)
            context.delete(event)
            context.delete(template)
        }
    }

    /// Removes every past occurrence represented by the current Event and
    /// advances its template until the persisted current occurrence is on or
    /// after `date`. The entire catch-up is saved as one transition.
    @discardableResult
    static func advance(
        _ event: Event,
        through date: Date,
        at transitionDate: Date = .now,
        in context: ModelContext,
        calendar: Calendar = .autoupdatingCurrent
    ) throws -> Event {
        try perform(in: context) {
            try advanceCurrentEvent(
                event,
                through: date,
                at: transitionDate,
                in: context,
                calendar: calendar
            )
        }
    }

    /// Applies startup/foreground maintenance to a fetched set of past Events.
    /// All one-time deletions and recurrence catch-ups commit together.
    static func removePastEventOccurrences(
        _ events: [Event],
        before date: Date,
        at transitionDate: Date = .now,
        in context: ModelContext,
        calendar: Calendar = .autoupdatingCurrent
    ) throws {
        try perform(in: context) {
            let cutoff = calendar.startOfDay(for: date)
            for event in events where event.scheduledDate < cutoff {
                if event.recurrenceTemplate == nil {
                    context.delete(event)
                } else {
                    _ = try advanceCurrentEvent(
                        event,
                        through: cutoff,
                        at: transitionDate,
                        in: context,
                        calendar: calendar
                    )
                }
            }
        }
    }

    /// Stops future recurrence while retaining the current occurrence as a
    /// normal item. Completed Todo history also remains persisted.
    static func deleteTemplate(
        _ template: RecurrenceTemplate,
        in context: ModelContext
    ) throws {
        try perform(in: context) {
            for todo in template.todoOccurrences {
                todo.recurrenceTemplate = nil
                todo.recurrenceSequence = nil
            }
            for event in template.eventOccurrences {
                event.recurrenceTemplate = nil
                event.recurrenceSequence = nil
            }
            context.delete(template)
        }
    }

    private static func makeNextTodo(
        after current: Todo,
        from template: RecurrenceTemplate,
        createdAt: Date,
        calendar: Calendar
    ) throws -> Todo {
        let rule = try template.rule(calendar: calendar)
        let nextDate = try RecurrenceCalculator.nextDate(
            after: current.scheduledDate,
            using: rule,
            calendar: calendar
        )
        let nextSequence = try incrementedSequence(
            template.currentSequence
        )
        let next = Todo(
            title: template.title,
            notes: template.notes,
            scheduledDate: nextDate,
            createdAt: createdAt,
            order: current.order,
            projectOrder: current.projectOrder,
            calendar: calendar
        )
        next.project = template.project
        next.recurrenceSequence = nextSequence
        return next
    }

    private static func makeNextEvent(
        after current: Event,
        from template: RecurrenceTemplate,
        createdAt: Date,
        calendar: Calendar
    ) throws -> Event {
        let rule = try template.rule(calendar: calendar)
        let nextDay = try RecurrenceCalculator.nextDate(
            after: current.scheduledDate,
            using: rule,
            calendar: calendar
        )
        guard let startTimeSeconds = template.startTimeSeconds else {
            throw RecurrencePersistenceError.missingEventStartTime
        }
        let nextStart = try date(
            on: nextDay,
            wallTimeSeconds: startTimeSeconds,
            calendar: calendar
        )
        let nextEnd = try template.endTimeSeconds.map {
            try date(
                on: nextDay,
                wallTimeSeconds: $0,
                calendar: calendar
            )
        }
        let nextSequence = try incrementedSequence(
            template.currentSequence
        )
        let next = Event(
            title: template.title,
            notes: template.notes,
            scheduledDate: nextStart,
            endDate: nextEnd,
            createdAt: createdAt,
            order: current.order,
            projectOrder: current.projectOrder
        )
        next.project = template.project
        next.recurrenceSequence = nextSequence
        return next
    }

    private static func advanceCurrentEvent(
        _ event: Event,
        through date: Date,
        at transitionDate: Date,
        in context: ModelContext,
        calendar: Calendar
    ) throws -> Event {
        guard let template = event.recurrenceTemplate else {
            throw RecurrencePersistenceError.itemDoesNotRepeat
        }
        try validateCurrent(event, for: template)

        let cutoff = calendar.startOfDay(for: date)
        var current = event
        while current.scheduledDate < cutoff {
            let next = try makeNextEvent(
                after: current,
                from: template,
                createdAt: transitionDate,
                calendar: calendar
            )
            context.insert(next)
            next.recurrenceTemplate = template
            guard let nextSequence = next.recurrenceSequence else {
                throw RecurrencePersistenceError.sequenceMismatch
            }
            template.currentItemID = next.id
            template.currentSequence = nextSequence
            context.delete(current)
            current = next
        }
        return current
    }

    private static func validateCurrent(
        _ todo: Todo,
        for template: RecurrenceTemplate
    ) throws {
        guard template.itemType == .todo else {
            throw RecurrencePersistenceError.wrongItemType
        }
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

    private static func validateCurrent(
        _ event: Event,
        for template: RecurrenceTemplate
    ) throws {
        guard template.itemType == .event else {
            throw RecurrencePersistenceError.wrongItemType
        }
        guard template.currentItemID == event.id else {
            throw RecurrencePersistenceError.itemIsNotCurrent
        }
        guard event.recurrenceSequence == template.currentSequence else {
            throw RecurrencePersistenceError.sequenceMismatch
        }
        guard template.eventOccurrences.count == 1,
              template.eventOccurrences.first?.id == event.id else {
            throw RecurrencePersistenceError.invalidCurrentOccurrences
        }
        try validate(order: event.order)
    }

    private static func eventTimes(
        for event: Event,
        calendar: Calendar
    ) throws -> (start: Int, end: Int?) {
        let startDay = calendar.startOfDay(for: event.scheduledDate)
        let start = wallTimeSeconds(
            for: event.scheduledDate,
            calendar: calendar
        )

        guard let endDate = event.endDate else {
            return (start, nil)
        }
        guard calendar.isDate(endDate, inSameDayAs: startDay) else {
            throw RecurrencePersistenceError.eventCrossesDateBoundary
        }

        let end = wallTimeSeconds(for: endDate, calendar: calendar)
        guard end >= start else {
            throw RecurrencePersistenceError.eventEndsBeforeItStarts
        }
        return (start, end)
    }

    private static func wallTimeSeconds(
        for date: Date,
        calendar: Calendar
    ) -> Int {
        let components = calendar.dateComponents(
            [.hour, .minute, .second],
            from: date
        )
        return (components.hour ?? 0) * 3_600
            + (components.minute ?? 0) * 60
            + (components.second ?? 0)
    }

    private static func date(
        on day: Date,
        wallTimeSeconds: Int,
        calendar: Calendar
    ) throws -> Date {
        let hour = wallTimeSeconds / 3_600
        let minute = wallTimeSeconds % 3_600 / 60
        let second = wallTimeSeconds % 60
        guard let date = calendar.date(
            bySettingHour: hour,
            minute: minute,
            second: second,
            of: calendar.startOfDay(for: day)
        ) else {
            throw RecurrencePersistenceError.eventTimeCalculationFailed
        }
        return date
    }

    private static func incrementedSequence(
        _ sequence: Int
    ) throws -> Int {
        let (next, overflow) = sequence.addingReportingOverflow(1)
        guard !overflow else {
            throw RecurrencePersistenceError.sequenceOverflow
        }
        return next
    }

    private static func validate(order: String) throws {
        guard FractionalIndex.isValid(order) else {
            throw RecurrencePersistenceError.invalidOrder
        }
    }

    private static func perform<Result>(
        in context: ModelContext,
        _ changes: () throws -> Result
    ) throws -> Result {
        do {
            let result = try changes()
            try context.save()
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
    case itemDoesNotRepeat
    case relativeEventUnsupported
    case eventCrossesDateBoundary
    case eventEndsBeforeItStarts
    case wrongItemType
    case itemIsNotCurrent
    case sequenceMismatch
    case todoAlreadyCompleted
    case todoNotCompleted
    case invalidCurrentOccurrences
    case invalidStoredMode(String)
    case invalidStoredUnit(String)
    case missingEventStartTime
    case eventTimeCalculationFailed
    case sequenceOverflow
    case invalidOrder
    case invalidEventTime
    case persistenceFailed(String)

    var code: String {
        switch self {
        case .itemAlreadyRepeats: "RECURRENCE-PERSIST-001"
        case .itemDoesNotRepeat: "RECURRENCE-PERSIST-017"
        case .relativeEventUnsupported: "RECURRENCE-PERSIST-002"
        case .eventCrossesDateBoundary: "RECURRENCE-PERSIST-003"
        case .eventEndsBeforeItStarts: "RECURRENCE-PERSIST-004"
        case .wrongItemType: "RECURRENCE-PERSIST-005"
        case .itemIsNotCurrent: "RECURRENCE-PERSIST-006"
        case .sequenceMismatch: "RECURRENCE-PERSIST-007"
        case .todoAlreadyCompleted: "RECURRENCE-PERSIST-008"
        case .todoNotCompleted: "RECURRENCE-PERSIST-019"
        case .invalidCurrentOccurrences: "RECURRENCE-PERSIST-009"
        case .invalidStoredMode: "RECURRENCE-PERSIST-010"
        case .invalidStoredUnit: "RECURRENCE-PERSIST-011"
        case .missingEventStartTime: "RECURRENCE-PERSIST-012"
        case .eventTimeCalculationFailed: "RECURRENCE-PERSIST-013"
        case .sequenceOverflow: "RECURRENCE-PERSIST-014"
        case .invalidOrder: "RECURRENCE-PERSIST-015"
        case .invalidEventTime: "RECURRENCE-PERSIST-018"
        case .persistenceFailed: "RECURRENCE-PERSIST-016"
        }
    }

    var errorDescription: String? {
        switch self {
        case .itemAlreadyRepeats:
            "This item already belongs to a recurrence template. (\(code))"
        case .itemDoesNotRepeat:
            "Nagare couldn't advance an item without a recurrence template. (\(code))"
        case .relativeEventUnsupported:
            "Events can only use absolute recurrence. (\(code))"
        case .eventCrossesDateBoundary:
            "Repeating Events must start and end on the same day. (\(code))"
        case .eventEndsBeforeItStarts:
            "A repeating Event cannot end before it starts. (\(code))"
        case .wrongItemType:
            "The recurrence template has an unexpected item type. (\(code))"
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
        case .missingEventStartTime:
            "The repeating Event template is missing its start time. (\(code))"
        case .eventTimeCalculationFailed:
            "Nagare couldn't apply the Event time to its next date. (\(code))"
        case .sequenceOverflow:
            "The recurrence occurrence counter cannot advance further. (\(code))"
        case .invalidOrder:
            "The current occurrence has an invalid saved position. (\(code))"
        case .invalidEventTime:
            "A repeating Event must use a valid same-day time. (\(code))"
        case .persistenceFailed(let message):
            "Nagare couldn't save the recurrence transition. \(message) (\(code))"
        }
    }
}
