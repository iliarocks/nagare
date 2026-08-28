import Foundation
import SwiftData

@Model
final class RecurrenceTemplate: Note, SyncRecord {
    #Index<RecurrenceTemplate>([\.id])

    @Attribute(.preserveValueOnDeletion) var id: UUID = UUID()
    /// Temporary V3 bridge field. Active templates always contain "todo".
    var itemTypeRawValue: String = "todo"
    var title: String = ""
    var notes: String?
    var modeRawValue: String = RecurrenceMode.relative.rawValue
    var unitRawValue: String = RecurrenceUnit.day.rawValue
    var interval: Int = 1
    var anchors: [Int] = []
    var reference: Date?
    var startTimeSeconds: Int?
    var endTimeSeconds: Int?
    var currentItemID: UUID = UUID()
    var currentSequence: Int = 0
    var createdAt: Date = Date.now
    var modifiedAt: Date?
    var syncRecordID: UUID?
    var project: Project?

    @Relationship(
        deleteRule: .nullify,
        originalName: "todoOccurrences",
        inverse: \Todo.recurrenceTemplate
    )
    private var storedTodoOccurrences: [Todo]?

    @Relationship(
        deleteRule: .nullify,
        originalName: "eventOccurrences",
        inverse: \Event.recurrenceTemplate
    )
    private var storedEventOccurrences: [Event]?

    var todoOccurrences: [Todo] { storedTodoOccurrences ?? [] }
    var eventOccurrences: [Event] { storedEventOccurrences ?? [] }

    init(
        id: UUID = UUID(),
        title: String,
        notes: String?,
        rule: RecurrenceRule,
        startTimeSeconds: Int? = nil,
        endTimeSeconds: Int? = nil,
        currentItemID: UUID,
        currentSequence: Int = 0,
        createdAt: Date = .now
    ) {
        self.id = id
        self.itemTypeRawValue = "todo"
        self.title = title
        self.notes = notes
        self.modeRawValue = rule.mode.rawValue
        self.unitRawValue = rule.unit.rawValue
        self.interval = rule.interval
        self.anchors = rule.anchors
        self.reference = rule.reference
        self.startTimeSeconds = startTimeSeconds
        self.endTimeSeconds = endTimeSeconds
        self.currentItemID = currentItemID
        self.currentSequence = currentSequence
        self.createdAt = createdAt
        self.modifiedAt = createdAt
        self.syncRecordID = UUID()
        self.project = nil
        self.storedTodoOccurrences = []
        self.storedEventOccurrences = []
    }

    func rule(
        calendar: Calendar = .autoupdatingCurrent
    ) throws -> RecurrenceRule {
        guard let mode = RecurrenceMode(rawValue: modeRawValue) else {
            throw RecurrencePersistenceError.invalidStoredMode(modeRawValue)
        }
        guard let unit = RecurrenceUnit(rawValue: unitRawValue) else {
            throw RecurrencePersistenceError.invalidStoredUnit(unitRawValue)
        }

        switch mode {
        case .relative:
            return try RecurrenceRule.relative(
                every: interval,
                unit: unit
            )
        case .absolute:
            guard let reference else {
                throw RecurrenceError.missingReference
            }
            return try RecurrenceRule.absolute(
                every: interval,
                unit: unit,
                anchors: anchors,
                reference: reference,
                calendar: calendar
            )
        }
    }
}
