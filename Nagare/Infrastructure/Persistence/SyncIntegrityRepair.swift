import Foundation
import SwiftData

struct SyncIntegrityRepairReport: Equatable, Sendable {
    var duplicateProjectsRemoved = 0
    var duplicateTodosRemoved = 0
    var duplicateEventsRemoved = 0
    var duplicateTemplatesRemoved = 0
    var recurrenceConflictsRepaired = 0
    var syncRecordIDsAssigned = 0

    var madeChanges: Bool {
        duplicateProjectsRemoved > 0
            || duplicateTodosRemoved > 0
            || duplicateEventsRemoved > 0
            || duplicateTemplatesRemoved > 0
            || recurrenceConflictsRepaired > 0
            || syncRecordIDsAssigned > 0
    }
}

/// Restores invariants that CloudKit cannot enforce while importing records
/// asynchronously. Every rule is deterministic and idempotent: two devices
/// presented with the same records select the same canonical result.
@MainActor
enum SyncIntegrityRepair {
    static func repair(
        in context: ModelContext,
        at modificationDate: Date = .now
    ) throws -> SyncIntegrityRepairReport {
        var report = SyncIntegrityRepairReport()

        let projects = try context.fetch(FetchDescriptor<Project>())
        let templates = try context.fetch(
            FetchDescriptor<RecurrenceTemplate>()
        )
        let todos = try context.fetch(FetchDescriptor<Todo>())
        let events = try context.fetch(FetchDescriptor<Event>())

        // SwiftData object identifiers are store-local implementation details.
        // Assign every record a replicated physical identity before resolving
        // duplicates so exact timestamp ties converge on every device.
        report.syncRecordIDsAssigned += assignMissingSyncRecordIDs(projects)
        report.syncRecordIDsAssigned += assignMissingSyncRecordIDs(templates)
        report.syncRecordIDsAssigned += assignMissingSyncRecordIDs(todos)
        report.syncRecordIDsAssigned += assignMissingSyncRecordIDs(events)

        report.duplicateProjectsRemoved = deduplicateProjects(
            projects,
            in: context
        )

        report.duplicateTemplatesRemoved = deduplicateTemplates(
            templates,
            in: context
        )

        report.duplicateTodosRemoved = deduplicateRecords(
            todos,
            in: context
        )

        report.duplicateEventsRemoved = deduplicateRecords(
            events,
            in: context
        )

        let survivingTemplates = try context.fetch(
            FetchDescriptor<RecurrenceTemplate>()
        )
        for template in survivingTemplates {
            switch template.itemType {
            case .todo:
                report.recurrenceConflictsRepaired += repairTodoRecurrence(
                    template,
                    in: context,
                    at: modificationDate
                )
            case .event:
                report.recurrenceConflictsRepaired += repairEventRecurrence(
                    template,
                    in: context
                )
            case nil:
                // Unknown future item kinds must remain intact for forward
                // compatibility. An older client has no authority to rewrite
                // data it cannot interpret.
                continue
            }
        }

        guard context.hasChanges else { return report }
        try SwiftDataTransaction.save(
            context,
            at: modificationDate
        )
        return report
    }

    private static func assignMissingSyncRecordIDs<Record>(
        _ records: [Record]
    ) -> Int where Record: PersistentModel & SyncRecord {
        var assigned = 0
        for record in records where record.syncRecordID == nil {
            record.syncRecordID = UUID()
            assigned += 1
        }
        return assigned
    }

    private static func deduplicateProjects(
        _ projects: [Project],
        in context: ModelContext
    ) -> Int {
        var removed = 0

        for group in groupsWithDuplicateIDs(projects) {
            let canonical = canonicalRecord(in: group)
            for duplicate in group where duplicate !== canonical {
                for todo in duplicate.todos where todo.project === duplicate {
                    todo.project = canonical
                }
                for event in duplicate.events where event.project === duplicate {
                    event.project = canonical
                }
                for template in duplicate.recurrenceTemplates
                where template.project === duplicate {
                    template.project = canonical
                }
                context.delete(duplicate)
                removed += 1
            }
        }

        return removed
    }

    private static func deduplicateTemplates(
        _ templates: [RecurrenceTemplate],
        in context: ModelContext
    ) -> Int {
        var removed = 0

        for group in groupsWithDuplicateIDs(templates) {
            let canonical = canonicalRecord(in: group)
            for duplicate in group where duplicate !== canonical {
                for todo in duplicate.todoOccurrences
                where todo.recurrenceTemplate === duplicate {
                    todo.recurrenceTemplate = canonical
                }
                for event in duplicate.eventOccurrences
                where event.recurrenceTemplate === duplicate {
                    event.recurrenceTemplate = canonical
                }
                context.delete(duplicate)
                removed += 1
            }
        }

        return removed
    }

    private static func deduplicateRecords<Record>(
        _ records: [Record],
        in context: ModelContext
    ) -> Int where Record: PersistentModel & SyncRecord {
        var removed = 0

        for group in groupsWithDuplicateIDs(records) {
            let canonical = canonicalRecord(in: group)
            for duplicate in group where duplicate !== canonical {
                context.delete(duplicate)
                removed += 1
            }
        }

        return removed
    }

    private static func repairTodoRecurrence(
        _ template: RecurrenceTemplate,
        in context: ModelContext,
        at modificationDate: Date
    ) -> Int {
        let sequenced = template.todoOccurrences.compactMap { todo in
            todo.recurrenceSequence.map { (sequence: $0, todo: todo) }
        }
        guard let highestSequence = sequenced.map(\.sequence).max() else {
            return 0
        }

        // A template may arrive before its new current occurrence. Preserve
        // everything until the referenced sequence is available locally.
        guard template.currentSequence <= highestSequence else { return 0 }

        let highest = sequenced
            .filter { $0.sequence == highestSequence }
            .map(\.todo)
        let activeHighest = highest.filter { $0.completedAt == nil }
        guard !activeHighest.isEmpty else {
            // The successor may still be in flight. Deleting completed data
            // here would turn an eventually consistent state into data loss.
            return 0
        }

        var repairs = 0
        let current = canonicalOccurrence(
            among: activeHighest,
            preferredID: template.currentSequence == highestSequence
                ? template.currentItemID
                : nil
        )

        for sequence in Set(sequenced.map(\.sequence)).sorted() {
            let occurrences = sequenced
                .filter { $0.sequence == sequence }
                .map(\.todo)

            if sequence == highestSequence {
                for duplicate in occurrences where duplicate !== current {
                    context.delete(duplicate)
                    repairs += 1
                }
                continue
            }

            let completed = occurrences.filter { $0.completedAt != nil }
            let canonical = completed.isEmpty
                ? canonicalRecord(in: occurrences)
                : canonicalRecord(in: completed)

            if canonical.completedAt == nil {
                let successorDate = sequenced
                    .filter { $0.sequence > sequence }
                    .map(\.todo.createdAt)
                    .min() ?? modificationDate
                canonical.completedAt = successorDate
                repairs += 1
            }

            for duplicate in occurrences where duplicate !== canonical {
                context.delete(duplicate)
                repairs += 1
            }
        }

        if template.currentSequence != highestSequence
            || template.currentItemID != current.id {
            template.currentSequence = highestSequence
            template.currentItemID = current.id
            repairs += 1
        }

        return repairs
    }

    private static func repairEventRecurrence(
        _ template: RecurrenceTemplate,
        in context: ModelContext
    ) -> Int {
        let sequenced = template.eventOccurrences.compactMap { event in
            event.recurrenceSequence.map { (sequence: $0, event: event) }
        }
        guard let highestSequence = sequenced.map(\.sequence).max() else {
            return 0
        }
        guard template.currentSequence <= highestSequence else { return 0 }

        let highest = sequenced
            .filter { $0.sequence == highestSequence }
            .map(\.event)
        let current = canonicalOccurrence(
            among: highest,
            preferredID: template.currentSequence == highestSequence
                ? template.currentItemID
                : nil
        )

        var repairs = 0
        for occurrence in sequenced.map(\.event) where occurrence !== current {
            context.delete(occurrence)
            repairs += 1
        }

        if template.currentSequence != highestSequence
            || template.currentItemID != current.id {
            template.currentSequence = highestSequence
            template.currentItemID = current.id
            repairs += 1
        }

        return repairs
    }

    private static func canonicalOccurrence<Record>(
        among records: [Record],
        preferredID: UUID?
    ) -> Record where Record: PersistentModel & SyncRecord {
        if let preferredID,
           let preferred = records.first(where: { $0.id == preferredID }) {
            return preferred
        }
        return canonicalRecord(in: records)
    }

    private static func groupsWithDuplicateIDs<Record>(
        _ records: [Record]
    ) -> [[Record]] where Record: PersistentModel & SyncRecord {
        Dictionary(grouping: records, by: \.id)
            .values
            .filter { $0.count > 1 }
    }

    private static func canonicalRecord<Record>(
        in records: [Record]
    ) -> Record where Record: PersistentModel & SyncRecord {
        precondition(!records.isEmpty)

        return records.max { first, second in
            if first.syncModificationDate != second.syncModificationDate {
                return first.syncModificationDate < second.syncModificationDate
            }
            if first.createdAt != second.createdAt {
                return first.createdAt < second.createdAt
            }
            if first.syncRecordID != second.syncRecordID {
                return (first.syncRecordID?.uuidString ?? "")
                    < (second.syncRecordID?.uuidString ?? "")
            }
            return persistentIdentity(first) < persistentIdentity(second)
        }!
    }

    private static func persistentIdentity<Record>(
        _ record: Record
    ) -> String where Record: PersistentModel {
        String(describing: record.persistentModelID)
    }
}
