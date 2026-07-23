import Foundation
import SwiftData

@Model
final class Todo: Note {
    @Attribute(.unique) var id: UUID
    var title: String
    var notes: String?
    var scheduledDate: Date
    var completedAt: Date?
    var createdAt: Date
    var order: String
    var recurrenceSequence: Int?
    var recurrenceTemplate: RecurrenceTemplate?

    init(
        id: UUID = UUID(),
        title: String,
        notes: String? = nil,
        scheduledDate: Date = .now,
        completedAt: Date? = nil,
        createdAt: Date = .now,
        order: String,
        calendar: Calendar = .autoupdatingCurrent
    ) {
        self.id = id
        self.title = title
        self.notes = notes
        self.scheduledDate = calendar.startOfDay(for: scheduledDate)
        self.completedAt = completedAt
        self.createdAt = createdAt
        self.order = order
        self.recurrenceSequence = nil
        self.recurrenceTemplate = nil
    }
}
