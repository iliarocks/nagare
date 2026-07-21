import Foundation
import SwiftData

@Model
final class Event: NoteEditable {
    @Attribute(.unique) var id: UUID
    var title: String
    var notes: String?
    var startDate: Date
    var endDate: Date?
    var createdAt: Date
    var sortOrder: Int64 = 0

    init(
        id: UUID = UUID(),
        title: String,
        notes: String? = nil,
        startDate: Date,
        endDate: Date? = nil,
        createdAt: Date = .now,
        sortOrder: Int64 = 0
    ) {
        self.id = id
        self.title = title
        self.notes = notes
        self.startDate = startDate
        self.endDate = endDate
        self.createdAt = createdAt
        self.sortOrder = sortOrder
    }
}
