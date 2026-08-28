import Foundation
import SwiftData

@Model
final class Todo: Note, SyncRecord {
    #Index<Todo>([\.id])

    @Attribute(.preserveValueOnDeletion) var id: UUID = UUID()
    var title: String = ""
    var notes: String?
    var scheduledDate: Date = Date.now
    var includesTime: Bool = false
    var endDate: Date?
    var calendarIdentifier: String?
    var completedAt: Date?
    var createdAt: Date = Date.now
    var modifiedAt: Date?
    var syncRecordID: UUID?
    var order: String = ""
    var projectOrder: String?
    var recurrenceSequence: Int?
    var recurrenceTemplate: RecurrenceTemplate?
    var project: Project?

    init(
        id: UUID = UUID(),
        title: String,
        notes: String? = nil,
        scheduledDate: Date = .now,
        includesTime: Bool = false,
        endDate: Date? = nil,
        calendarIdentifier: String? = nil,
        completedAt: Date? = nil,
        createdAt: Date = .now,
        order: String,
        projectOrder: String? = nil,
        calendar: Calendar = .autoupdatingCurrent
    ) {
        self.id = id
        self.title = title
        self.notes = notes
        self.scheduledDate = includesTime
            ? scheduledDate
            : calendar.startOfDay(for: scheduledDate)
        self.includesTime = includesTime
        self.endDate = includesTime ? endDate : nil
        self.calendarIdentifier = calendarIdentifier
        self.completedAt = completedAt
        self.createdAt = createdAt
        self.modifiedAt = createdAt
        self.syncRecordID = UUID()
        self.order = order
        self.projectOrder = projectOrder
        self.recurrenceSequence = nil
        self.recurrenceTemplate = nil
        self.project = nil
    }
}
