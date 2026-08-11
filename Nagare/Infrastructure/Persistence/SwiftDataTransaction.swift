import SwiftData

/// Central transaction adapter for the remaining record-editing workflows.
/// Every failed save restores the context before the error crosses the I/O
/// boundary, so callers never continue with uncommitted in-memory mutations.
@MainActor
enum SwiftDataTransaction {
    static func save(_ context: ModelContext) throws {
        do {
            try context.save()
        } catch {
            context.rollback()
            throw error
        }
    }

    static func perform<Result>(
        in context: ModelContext,
        _ changes: () throws -> Result
    ) throws -> Result {
        do {
            let result = try changes()
            try context.save()
            return result
        } catch {
            context.rollback()
            throw error
        }
    }
}
