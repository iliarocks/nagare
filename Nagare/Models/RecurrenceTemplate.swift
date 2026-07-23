import Foundation
import SwiftData

enum RecurrenceItemType: String, Codable, Sendable {
    case todo
    case event
}

@Model
final class RecurrenceTemplate: Note {
    @Attribute(.unique) var id: UUID
    var itemTypeRawValue: String
    var title: String
    var notes: String?
    var modeRawValue: String
    var unitRawValue: String
    var interval: Int
    var anchors: [Int]
    var reference: Date?
    var startTimeSeconds: Int?
    var endTimeSeconds: Int?
    var currentItemID: UUID
    var currentSequence: Int
    var createdAt: Date

    @Relationship(deleteRule: .nullify, inverse: \Todo.recurrenceTemplate)
    var todoOccurrences: [Todo]

    @Relationship(deleteRule: .nullify, inverse: \Event.recurrenceTemplate)
    var eventOccurrences: [Event]

    init(
        id: UUID = UUID(),
        itemType: RecurrenceItemType,
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
        self.itemTypeRawValue = itemType.rawValue
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
        self.todoOccurrences = []
        self.eventOccurrences = []
    }

    var itemType: RecurrenceItemType? {
        RecurrenceItemType(rawValue: itemTypeRawValue)
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
