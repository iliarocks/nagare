import Foundation
import SwiftData

/// Pure record-to-value translation shared by sync reconciliation and virtual
/// recurrence projection. Encoding every tie field here prevents two policies
/// from quietly disagreeing about replicated identity.
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

    static func recurrenceProjectionInput(
        templates: [RecurrenceTemplate],
        todos: [Todo]
    ) -> RecurrenceProjectionInput {
        RecurrenceProjectionInput(
            templates: templates.map {
                RecurrenceProjectionTemplateSnapshot(
                    metadata: templateMetadata($0),
                    modeRawValue: $0.modeRawValue,
                    unitRawValue: $0.unitRawValue,
                    interval: $0.interval,
                    anchors: $0.anchors,
                    reference: $0.reference,
                    repeatUntil: $0.repeatUntil,
                    startTimeSeconds: $0.startTimeSeconds,
                    endTimeSeconds: $0.endTimeSeconds,
                    currentItemID: $0.currentItemID,
                    currentSequence: $0.currentSequence
                )
            },
            occurrences: todos.map {
                RecurrenceProjectionOccurrenceSnapshot(
                    metadata: todoMetadata($0),
                    scheduledDate: $0.scheduledDate,
                    completedAt: $0.completedAt,
                    order: $0.order,
                    recurrenceSequence: $0.recurrenceSequence,
                    recurrenceTemplateID: $0.recurrenceTemplate?.id
                )
            }
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
