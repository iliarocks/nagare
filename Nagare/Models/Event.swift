import Foundation
import SwiftData

@Model
final class Event: Note {
    @Attribute(.unique) var id: UUID
    var title: String
    var notes: String?
    var scheduledDate: Date
    var endDate: Date?
    var createdAt: Date
    var order: String
    var recurrenceSequence: Int?
    var recurrenceTemplate: RecurrenceTemplate?

    init(
        id: UUID = UUID(),
        title: String,
        notes: String? = nil,
        scheduledDate: Date,
        endDate: Date? = nil,
        createdAt: Date = .now,
        order: String
    ) {
        self.id = id
        self.title = title
        self.notes = notes
        self.scheduledDate = scheduledDate
        self.endDate = endDate
        self.createdAt = createdAt
        self.order = order
        self.recurrenceSequence = nil
        self.recurrenceTemplate = nil
    }
}
