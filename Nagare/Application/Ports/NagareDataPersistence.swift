import Foundation

nonisolated protocol NagareDataReading: AnyObject {
    func load() throws -> NagareDataSnapshot
}

nonisolated protocol NagareDataWriting: AnyObject {
    func importData(
        _ plan: NagareDataImportPlan,
        at date: Date
    ) throws
    func upsertItem(
        _ plan: ItemUpsertPlan,
        at date: Date
    ) throws -> ItemID
    func upsertProject(
        _ plan: ProjectUpsertPlan,
        at date: Date
    ) throws -> UUID
    func updateNote(
        _ id: NoteRecordID,
        title: String,
        notes: String?,
        at date: Date
    ) throws
    func updateProject(
        _ id: UUID,
        title: String,
        notes: String?,
        at date: Date
    ) throws
    func saveItemOrdering(
        _ changes: [ItemOrderingChange],
        at date: Date
    ) throws
    func saveProjectOrdering(
        _ changes: [ProjectOrderingChange],
        at date: Date
    ) throws
    func saveProjectItemOrdering(
        _ changes: [ProjectItemOrderingChange],
        at date: Date
    ) throws
    func deleteProject(_ id: UUID, at date: Date) throws
    func completeTodo(_ id: UUID, at date: Date) throws
    func reinstateTodo(
        _ plan: TodoReinstatementPlan,
        at transactionDate: Date
    ) throws
    func deleteCompletedTodo(_ id: UUID, at date: Date) throws
    func deleteItem(_ id: ItemID, at date: Date) throws
    func deleteItems(_ ids: [ItemID], at date: Date) throws
    func deleteRecurrenceTemplate(_ id: UUID, at date: Date) throws
    func assign(_ plan: ProjectAssignmentPlan, at date: Date) throws
    func assign(_ plan: ProjectAssignmentBatchPlan, at date: Date) throws
    func updateRecurrenceTemplate(
        _ id: UUID,
        rule: RecurrenceRule,
        startTimeSeconds: Int?,
        endTimeSeconds: Int?,
        at date: Date
    ) throws
}
