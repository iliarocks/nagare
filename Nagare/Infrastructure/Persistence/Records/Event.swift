import Foundation
import SwiftData

@Model
final class Event: Note, SyncRecord {
    #Index<Event>([\.id])

    @Attribute(.preserveValueOnDeletion) var id: UUID = UUID()
    var title: String = ""
    var notes: String?
    var scheduledDate: Date = Date.now
    var endDate: Date?
    var calendarIdentifier: String?
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
        scheduledDate: Date,
        endDate: Date? = nil,
        calendarIdentifier: String? = nil,
        createdAt: Date = .now,
        order: String,
        projectOrder: String? = nil
    ) {
        self.id = id
        self.title = title
        self.notes = notes
        self.scheduledDate = scheduledDate
        self.endDate = endDate
        self.calendarIdentifier = calendarIdentifier
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
