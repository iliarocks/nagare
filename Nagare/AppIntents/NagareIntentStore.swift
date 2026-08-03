import AppIntents
import CoreSpotlight
import Foundation
import SwiftData

enum NagareIntentItemKind: String, Sendable {
    case todo
    case event
}

struct NagareIntentItemSnapshot: Sendable {
    let id: UUID
    let kind: NagareIntentItemKind
    let title: String
    let notes: String?
    let scheduledDate: Date
    let endDate: Date?
    let createdAt: Date
    let completedAt: Date?
    let recurrence: RecurrenceRule?
}

struct NagareIntentMutationResult: Sendable {
    let item: NagareIntentItemSnapshot
    let nextOccurrence: NagareIntentItemSnapshot?
}

struct NagareIntentDeletionResult: Sendable {
    let title: String
    let nextOccurrence: NagareIntentItemSnapshot?
}

@MainActor
final class NagareIntentStore: @unchecked Sendable {
    let modelContainer: ModelContainer
    let modelContext: ModelContext
    nonisolated(unsafe) let searchableIndex: CSSearchableIndex

    init(modelContainer: ModelContainer) {
        self.modelContainer = modelContainer
        self.modelContext = modelContainer.mainContext
        self.searchableIndex = CSSearchableIndex(name: "NagareItems")
    }

    func createTodo(
        title: String,
        notes: String?,
        scheduledDate: Date,
        recurrence: RecurrenceRule?
    ) throws -> Todo {
        let order = try ItemOrdering.nextOrder(in: modelContext)
        let todo = Todo(
            title: title,
            notes: notes,
            scheduledDate: scheduledDate,
            order: order
        )
        modelContext.insert(todo)

        if let recurrence {
            _ = try RecurrencePersistence.createTemplate(
                for: todo,
                rule: recurrence,
                in: modelContext
            )
        } else {
            try modelContext.save()
        }

        return todo
    }

    func createEvent(
        title: String,
        notes: String?,
        scheduledDate: Date,
        endDate: Date?,
        recurrence: RecurrenceRule?
    ) throws -> Event {
        let order = try ItemOrdering.nextOrder(in: modelContext)
        let event = Event(
            title: title,
            notes: notes,
            scheduledDate: scheduledDate,
            endDate: endDate,
            order: order
        )
        modelContext.insert(event)

        if let recurrence {
            _ = try RecurrencePersistence.createTemplate(
                for: event,
                rule: recurrence,
                in: modelContext
            )
        } else {
            try modelContext.save()
        }

        return event
    }

    func todoSnapshots(
        matching identifiers: [UUID]? = nil
    ) throws -> [NagareIntentItemSnapshot] {
        let todos = try modelContext.fetch(FetchDescriptor<Todo>())
        let identifierSet = identifiers.map(Set.init)
        return try todos
            .filter { identifierSet?.contains($0.id) ?? true }
            .map(snapshot)
    }

    func eventSnapshots(
        matching identifiers: [UUID]? = nil
    ) throws -> [NagareIntentItemSnapshot] {
        let events = try modelContext.fetch(FetchDescriptor<Event>())
        let identifierSet = identifiers.map(Set.init)
        return try events
            .filter { identifierSet?.contains($0.id) ?? true }
            .map(snapshot)
    }

    func todayItemSnapshots(
        on date: Date = .now,
        calendar: Calendar = .autoupdatingCurrent
    ) throws -> [NagareIntentItemSnapshot] {
        try performMaintenance(on: date, calendar: calendar)

        let today = calendar.startOfDay(for: date)
        guard let tomorrow = calendar.date(
            byAdding: .day,
            value: 1,
            to: today
        ) else {
            throw NagareIntentError.dateCouldNotBeResolved
        }

        let todos = try modelContext.fetch(FetchDescriptor<Todo>()).filter {
            $0.completedAt == nil && $0.scheduledDate < tomorrow
        }
        let events = try modelContext.fetch(FetchDescriptor<Event>()).filter {
            $0.scheduledDate >= today && $0.scheduledDate < tomorrow
        }

        return try Item.ordered(todos: todos, events: events).map { item in
            switch item {
            case .todo(let todo):
                try snapshot(todo)
            case .event(let event):
                try snapshot(event)
            }
        }
    }

    func todayEventSnapshots(
        on date: Date = .now,
        calendar: Calendar = .autoupdatingCurrent
    ) throws -> [NagareIntentItemSnapshot] {
        try performMaintenance(on: date, calendar: calendar)

        let today = calendar.startOfDay(for: date)
        guard let tomorrow = calendar.date(
            byAdding: .day,
            value: 1,
            to: today
        ) else {
            throw NagareIntentError.dateCouldNotBeResolved
        }

        return try modelContext.fetch(FetchDescriptor<Event>())
            .filter {
                $0.scheduledDate >= today && $0.scheduledDate < tomorrow
            }
            .sorted { first, second in
                if first.scheduledDate != second.scheduledDate {
                    return first.scheduledDate < second.scheduledDate
                }
                return first.order < second.order
            }
            .map(snapshot)
    }

    func todayItemSnapshot(
        afterTitle title: String,
        on date: Date = .now,
        calendar: Calendar = .autoupdatingCurrent
    ) throws -> NagareIntentItemSnapshot? {
        let normalizedTitle = title.trimmingCharacters(
            in: .whitespacesAndNewlines.union(
                CharacterSet(charactersIn: "\"“”")
            )
        )
        let items = try todayItemSnapshots(on: date, calendar: calendar)
        let matchingIndices = items.indices.filter {
            items[$0].title.compare(
                normalizedTitle,
                options: [.caseInsensitive, .diacriticInsensitive]
            ) == .orderedSame
        }

        guard !matchingIndices.isEmpty else {
            throw NagareIntentError.itemNotOnToday
        }
        guard matchingIndices.count == 1,
              let index = matchingIndices.first else {
            throw NagareIntentError.ambiguousTodayItem
        }

        let nextIndex = items.index(after: index)
        return items.indices.contains(nextIndex) ? items[nextIndex] : nil
    }

    func setTodoCompletion(
        _ identifier: UUID,
        isCompleted: Bool,
        at date: Date = .now,
        calendar: Calendar = .autoupdatingCurrent
    ) throws -> NagareIntentMutationResult {
        let todo = try todo(identifiedBy: identifier)
        let next: Todo?

        if isCompleted {
            next = todo.completedAt == nil
                ? try RecurrencePersistence.complete(
                    todo,
                    at: date,
                    in: modelContext,
                    calendar: calendar
                )
                : nil
        } else {
            if todo.completedAt != nil {
                try RecurrencePersistence.reinstate(
                    todo,
                    on: date,
                    in: modelContext,
                    calendar: calendar
                )
            }
            next = nil
        }

        return try NagareIntentMutationResult(
            item: snapshot(todo),
            nextOccurrence: next.map(snapshot)
        )
    }

    func deleteTodos(
        identifiedBy identifiers: [UUID],
        at date: Date = .now,
        calendar: Calendar = .autoupdatingCurrent
    ) throws -> [NagareIntentDeletionResult] {
        let todos = try identifiers.map(todo(identifiedBy:))

        return try todos.map { todo in
            let title = todo.title
            if todo.completedAt != nil {
                try RecurrencePersistence.deleteCompleted(
                    todo,
                    in: modelContext
                )
                return NagareIntentDeletionResult(
                    title: title,
                    nextOccurrence: nil
                )
            }

            let next = try RecurrencePersistence.delete(
                todo,
                at: date,
                in: modelContext,
                calendar: calendar
            )
            return try NagareIntentDeletionResult(
                title: title,
                nextOccurrence: next.map(snapshot)
            )
        }
    }

    func deleteEvent(
        identifiedBy identifier: UUID,
        span: NagareEventSpan?,
        at date: Date = .now,
        calendar: Calendar = .autoupdatingCurrent
    ) throws -> NagareIntentDeletionResult {
        let event = try event(identifiedBy: identifier)
        let title = event.title

        guard event.recurrenceTemplate != nil else {
            _ = try RecurrencePersistence.delete(
                event,
                at: date,
                in: modelContext,
                calendar: calendar
            )
            return NagareIntentDeletionResult(
                title: title,
                nextOccurrence: nil
            )
        }

        switch span ?? .this {
        case .this:
            let next = try RecurrencePersistence.delete(
                event,
                at: date,
                in: modelContext,
                calendar: calendar
            )
            return try NagareIntentDeletionResult(
                title: title,
                nextOccurrence: next.map(snapshot)
            )
        case .future, .all:
            try RecurrencePersistence.deleteSeries(
                containing: event,
                in: modelContext
            )
            return NagareIntentDeletionResult(
                title: title,
                nextOccurrence: nil
            )
        }
    }

    func refreshSearchIndex() async throws {
        try await searchableIndex.deleteAllSearchableItems()
        try await searchableIndex.indexAppEntities([
            NagareReminderListEntity.nagare
        ])
        try await searchableIndex.indexAppEntities([
            NagareCalendarEntity.nagare
        ])
    }

    private func todo(identifiedBy identifier: UUID) throws -> Todo {
        guard let todo = try modelContext.fetch(FetchDescriptor<Todo>())
            .first(where: { $0.id == identifier }) else {
            throw NagareIntentError.itemNotFound
        }
        return todo
    }

    private func event(identifiedBy identifier: UUID) throws -> Event {
        guard let event = try modelContext.fetch(FetchDescriptor<Event>())
            .first(where: { $0.id == identifier }) else {
            throw NagareIntentError.itemNotFound
        }
        return event
    }

    private func performMaintenance(
        on date: Date,
        calendar: Calendar
    ) throws {
        try TodoMaintenance.rollUnfinishedTodosForward(
            in: modelContext,
            calendar: calendar,
            now: date
        )
        try EventMaintenance.deletePastEvents(
            in: modelContext,
            calendar: calendar,
            now: date
        )
    }

    private func snapshot(_ todo: Todo) throws -> NagareIntentItemSnapshot {
        NagareIntentItemSnapshot(
            id: todo.id,
            kind: .todo,
            title: todo.title,
            notes: todo.notes,
            scheduledDate: todo.scheduledDate,
            endDate: nil,
            createdAt: todo.createdAt,
            completedAt: todo.completedAt,
            recurrence: try todo.recurrenceTemplate?.rule()
        )
    }

    private func snapshot(_ event: Event) throws -> NagareIntentItemSnapshot {
        NagareIntentItemSnapshot(
            id: event.id,
            kind: .event,
            title: event.title,
            notes: event.notes,
            scheduledDate: event.scheduledDate,
            endDate: event.endDate,
            createdAt: event.createdAt,
            completedAt: nil,
            recurrence: try event.recurrenceTemplate?.rule()
        )
    }
}
