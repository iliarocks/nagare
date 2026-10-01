import Foundation
import SwiftData

/// Record-to-value translation for sync reconciliation, including the local
/// references needed to apply a plan to concrete SwiftData records.
@MainActor
enum SwiftDataSyncSnapshotMapper {
    static func project(_ record: Project) -> SyncProjectSnapshot {
        SyncProjectSnapshot(metadata: projectMetadata(record))
    }

    static func recurrenceTemplate(
        _ record: RecurrenceTemplate
    ) -> SyncRecurrenceTemplateSnapshot {
        SyncRecurrenceTemplateSnapshot(
            metadata: templateMetadata(record),
            currentItemID: record.currentItemID,
            currentSequence: record.currentSequence,
            projectID: record.project?.id
        )
    }

    static func todo(_ record: Todo) -> SyncTodoSnapshot {
        SyncTodoSnapshot(
            metadata: todoMetadata(record),
            completedAt: record.completedAt,
            recurrenceSequence: record.recurrenceSequence,
            recurrenceTemplateID: record.recurrenceTemplate?.id,
            projectID: record.project?.id
        )
    }

    static func reference<Record>(
        for record: Record,
        kind: SyncEntityKind
    ) -> SyncRecordReference where Record: PersistentModel {
        SyncRecordReference(
            kind: kind,
            localID: String(describing: ObjectIdentifier(record))
        )
    }

    private static func projectMetadata(
        _ record: Project
    ) -> SyncRecordMetadata {
        metadata(
            for: record,
            kind: .project,
            tieBreaker: [
                stable(record.title),
                stable(record.notes),
                stable(record.priority.rawValue),
                stable(record.order)
            ]
        )
    }

    private static func templateMetadata(
        _ record: RecurrenceTemplate
    ) -> SyncRecordMetadata {
        metadata(
            for: record,
            kind: .recurrenceTemplate,
            tieBreaker: [
                stable(record.title),
                stable(record.notes),
                stable(record.modeRawValue),
                stable(record.unitRawValue),
                stable(record.interval),
                stable(record.anchors),
                stable(record.reference),
                stable(record.repeatUntil),
                stable(record.startTimeSeconds),
                stable(record.endTimeSeconds),
                stable(record.currentItemID),
                stable(record.currentSequence),
                stable(record.project?.id)
            ]
        )
    }

    private static func todoMetadata(_ record: Todo) -> SyncRecordMetadata {
        metadata(
            for: record,
            kind: .todo,
            tieBreaker: [
                stable(record.title),
                stable(record.notes),
                stable(record.scheduledDate),
                stable(record.includesTime),
                stable(record.endDate),
                stable(record.calendarIdentifier),
                stable(record.completedAt),
                stable(record.order),
                stable(record.projectOrder),
                stable(record.recurrenceSequence),
                stable(record.recurrenceTemplate?.id),
                stable(record.project?.id)
            ]
        )
    }

    private static func metadata<Record>(
        for record: Record,
        kind: SyncEntityKind,
        tieBreaker: [String]
    ) -> SyncRecordMetadata where Record: PersistentModel & SyncRecord {
        SyncRecordMetadata(
            reference: reference(for: record, kind: kind),
            semanticID: record.id,
            physicalID: record.syncRecordID,
            createdAt: record.createdAt,
            modifiedAt: record.modifiedAt,
            stableTieBreaker: tieBreaker
        )
    }

    private static func stable(_ value: String) -> String {
        SyncStableValue.encode(value)
    }

    private static func stable(_ value: String?) -> String {
        SyncStableValue.encode(value)
    }

    private static func stable(_ value: Bool) -> String {
        SyncStableValue.encode(value)
    }

    private static func stable(_ value: Int) -> String {
        SyncStableValue.encode(value)
    }

    private static func stable(_ value: Int?) -> String {
        SyncStableValue.encode(value)
    }

    private static func stable(_ value: [Int]) -> String {
        SyncStableValue.encode(value)
    }

    private static func stable(_ value: Date) -> String {
        SyncStableValue.encode(value)
    }

    private static func stable(_ value: Date?) -> String {
        SyncStableValue.encode(value)
    }

    private static func stable(_ value: UUID) -> String {
        SyncStableValue.encode(value)
    }

    private static func stable(_ value: UUID?) -> String {
        SyncStableValue.encode(value)
    }
}
