import Observation
import SwiftUI

/// The app's single published source of truth. Its state is one immutable
/// value; every command runs through an orchestrator and replaces that value
/// only after the transaction commits.
@MainActor
@Observable
final class NagareDataStore {
    private(set) var snapshot: NagareDataSnapshot

    @ObservationIgnored
    private let orchestrator: NagareDataOrchestrator
    @ObservationIgnored
    private let calendarImportOrchestrator: CalendarImportOrchestrator

    init(
        orchestrator: NagareDataOrchestrator,
        calendarImportOrchestrator: CalendarImportOrchestrator
    ) throws {
        self.orchestrator = orchestrator
        self.calendarImportOrchestrator = calendarImportOrchestrator
        snapshot = try orchestrator.load()
    }

    var projects: [ProjectRecordSnapshot] { snapshot.canonicalProjects }
    var todos: [TodoRecordSnapshot] { snapshot.canonicalTodos }
    var events: [EventRecordSnapshot] { snapshot.canonicalEvents }
    var recurrenceTemplates: [RecurrenceTemplateRecordSnapshot] {
        snapshot.canonicalRecurrenceTemplates
    }

    @discardableResult
    func upsertItem(
        _ draft: ItemDraft,
        existingID: ItemID?,
        calendar: Calendar = .autoupdatingCurrent,
        at date: Date = .now
    ) throws -> ItemID {
        let result = try orchestrator.upsertItem(
            draft,
            existingID: existingID,
            calendar: calendar,
            at: date
        )
        snapshot = result.snapshot
        return result.id
    }

    @discardableResult
    func upsertProject(
        _ draft: ProjectDraft,
        existingID: UUID?,
        at date: Date = .now
    ) throws -> UUID {
        let result = try orchestrator.upsertProject(
            draft,
            existingID: existingID,
            at: date
        )
        snapshot = result.snapshot
        return result.id
    }

    func reload() throws {
        snapshot = try orchestrator.load()
    }

    func importPendingCalendarEvents(
        at date: Date = .now
    ) throws -> [EventRecordSnapshot] {
        let result = try calendarImportOrchestrator.importPending(at: date)
        snapshot = result.snapshot
        return result.events
    }

    func updateNote(
        _ id: NoteRecordID,
        title: String,
        notes: String?,
        at date: Date = .now
    ) throws {
        snapshot = try orchestrator.updateNote(
            id,
            title: title,
            notes: notes,
            at: date
        )
    }

    func updateProject(
        _ id: UUID,
        title: String,
        notes: String?,
        at date: Date = .now
    ) throws {
        snapshot = try orchestrator.updateProject(
            id,
            title: title,
            notes: notes,
            at: date
        )
    }

    func saveItemOrdering(
        _ changes: [ItemOrderingChange],
        at date: Date = .now
    ) throws {
        snapshot = try orchestrator.saveItemOrdering(changes, at: date)
    }

    func saveProjectOrdering(
        _ changes: [ProjectOrderingChange],
        at date: Date = .now
    ) throws {
        snapshot = try orchestrator.saveProjectOrdering(changes, at: date)
    }

    func reorderProjects(
        _ displayedIDs: [UUID],
        isPriority: Bool,
        at date: Date = .now
    ) throws {
        snapshot = try orchestrator.reorderProjects(
            displayedIDs,
            isPriority: isPriority,
            at: date
        )
    }

    func moveProjects(
        _ sourceIDs: [UUID],
        toPriority isPriority: Bool,
        before destinationID: UUID?,
        at date: Date = .now
    ) throws {
        snapshot = try orchestrator.moveProjects(
            sourceIDs,
            toPriority: isPriority,
            before: destinationID,
            at: date
        )
    }

    func moveProjectItems(
        _ sourceIDs: [ItemID],
        before destinationID: ItemID?,
        projectID: UUID,
        at date: Date = .now
    ) throws {
        snapshot = try orchestrator.moveProjectItems(
            sourceIDs,
            before: destinationID,
            projectID: projectID,
            at: date
        )
    }

    func deleteProject(_ id: UUID, at date: Date = .now) throws {
        snapshot = try orchestrator.deleteProject(id, at: date)
    }

    func completeTodo(_ id: UUID, at date: Date = .now) throws {
        snapshot = try orchestrator.completeTodo(id, at: date)
    }

    func reinstateTodo(
        _ id: UUID,
        on date: Date = .now,
        calendar: Calendar = .autoupdatingCurrent,
        at transactionDate: Date = .now
    ) throws {
        snapshot = try orchestrator.reinstateTodo(
            id,
            on: date,
            calendar: calendar,
            at: transactionDate
        )
    }

    func deleteCompletedTodo(_ id: UUID, at date: Date = .now) throws {
        snapshot = try orchestrator.deleteCompletedTodo(id, at: date)
    }

    func performMaintenance(
        at date: Date = .now,
        calendar: Calendar = .autoupdatingCurrent
    ) throws {
        snapshot = try orchestrator.performMaintenance(
            at: date,
            calendar: calendar
        )
    }

    func deleteItem(_ id: ItemID, at date: Date = .now) throws {
        snapshot = try orchestrator.deleteItem(id, at: date)
    }

    func deleteItems(_ ids: [ItemID], at date: Date = .now) throws {
        snapshot = try orchestrator.deleteItems(ids, at: date)
    }

    func deleteRecurrenceTemplate(
        _ id: UUID,
        at date: Date = .now
    ) throws {
        snapshot = try orchestrator.deleteRecurrenceTemplate(id, at: date)
    }

    func moveItems(
        _ sourceIDs: [ItemID],
        to destinationDate: Date,
        before destinationID: ItemID?,
        calendar: Calendar = .autoupdatingCurrent,
        at date: Date = .now
    ) throws {
        snapshot = try orchestrator.moveItems(
            sourceIDs,
            to: destinationDate,
            before: destinationID,
            calendar: calendar,
            at: date
        )
    }

    func updateEventSchedule(
        _ id: UUID,
        scheduledDate: Date,
        endDate: Date?,
        calendar: Calendar = .autoupdatingCurrent,
        at date: Date = .now
    ) throws {
        snapshot = try orchestrator.updateEventSchedule(
            id,
            scheduledDate: scheduledDate,
            endDate: endDate,
            calendar: calendar,
            at: date
        )
    }

    func assign(
        _ target: ProjectMoveRecordID,
        to projectID: UUID?,
        at date: Date = .now
    ) throws {
        snapshot = try orchestrator.assign(
            target,
            to: projectID,
            at: date
        )
    }

    func assign(
        _ targets: [ProjectMoveRecordID],
        to projectID: UUID?,
        at date: Date = .now
    ) throws {
        snapshot = try orchestrator.assign(
            targets,
            to: projectID,
            at: date
        )
    }

    func updateRecurrenceTemplate(
        _ id: UUID,
        rule: RecurrenceRule,
        eventStartTimeSeconds: Int?,
        eventEndTimeSeconds: Int?,
        at date: Date = .now
    ) throws {
        snapshot = try orchestrator.updateRecurrenceTemplate(
            id,
            rule: rule,
            eventStartTimeSeconds: eventStartTimeSeconds,
            eventEndTimeSeconds: eventEndTimeSeconds,
            at: date
        )
    }
}

private struct NagareDataStoreKey: EnvironmentKey {
    static let defaultValue: NagareDataStore? = nil
}

extension EnvironmentValues {
    fileprivate var nagareDataStore: NagareDataStore? {
        get { self[NagareDataStoreKey.self] }
        set { self[NagareDataStoreKey.self] = newValue }
    }
}

/// A required dependency at the point a view actually evaluates. Keeping the
/// raw Environment value optional lets SwiftUI project its writable key path;
/// exposing only this wrapper to views prevents silent optional commands.
@propertyWrapper
struct NagareDataStoreEnvironment: DynamicProperty {
    @Environment(\.nagareDataStore) private var value

    var wrappedValue: NagareDataStore {
        guard let value else {
            preconditionFailure(
                "NagareDataStore must be injected at the application root."
            )
        }
        return value
    }
}

extension View {
    func nagareDataStore(_ store: NagareDataStore) -> some View {
        environment(\.nagareDataStore, store)
    }
}
