import Foundation
import SwiftData

/// Central transaction adapter for the remaining record-editing workflows.
/// Every failed save restores the context before the error crosses the I/O
/// boundary, so callers never continue with uncommitted in-memory mutations.
@MainActor
enum SwiftDataTransaction {
    static func save(
        _ context: ModelContext,
        at modificationDate: Date = .now
    ) throws {
        do {
            stampPendingChanges(
                in: context,
                at: modificationDate
            )
            try context.save()
        } catch {
            context.rollback()
            throw error
        }
    }

    static func perform<Result>(
        in context: ModelContext,
        at modificationDate: Date = .now,
        _ changes: () throws -> Result
    ) throws -> Result {
        do {
            let result = try changes()
            stampPendingChanges(
                in: context,
                at: modificationDate
            )
            try context.save()
            return result
        } catch {
            context.rollback()
            throw error
        }
    }

    private static func stampPendingChanges(
        in context: ModelContext,
        at modificationDate: Date
    ) {
        var stampedObjects: Set<ObjectIdentifier> = []

        for model in context.insertedModelsArray + context.changedModelsArray {
            guard let record = model as? any SyncRecord else { continue }
            let identifier = ObjectIdentifier(record)
            guard stampedObjects.insert(identifier).inserted else { continue }
            record.modifiedAt = modificationDate
        }
    }
}
