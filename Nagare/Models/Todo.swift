import Foundation
import SwiftData

@Model
final class Todo {
    @Attribute(.unique) var id: UUID
    var title: String
    var scheduledDate: Date
    var completedAt: Date?
    var createdAt: Date

    init(
        id: UUID = UUID(),
        title: String,
        scheduledDate: Date = .now,
        completedAt: Date? = nil,
        createdAt: Date = .now
    ) {
        self.id = id
        self.title = title
        self.scheduledDate = Calendar.autoupdatingCurrent.startOfDay(for: scheduledDate)
        self.completedAt = completedAt
        self.createdAt = createdAt
    }
}
