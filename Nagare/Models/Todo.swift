import Foundation
import SwiftData

@Model
final class Todo {
    @Attribute(.unique) var id: UUID
    var title: String
    var notes: String?
    var scheduledDate: Date
    var completedAt: Date?
    var createdAt: Date

    init(
        id: UUID = UUID(),
        title: String,
        notes: String? = nil,
        scheduledDate: Date = .now,
        completedAt: Date? = nil,
        createdAt: Date = .now
    ) {
        self.id = id
        self.title = title
        self.notes = notes
        self.scheduledDate = Calendar.autoupdatingCurrent.startOfDay(for: scheduledDate)
        self.completedAt = completedAt
        self.createdAt = createdAt
    }
}
