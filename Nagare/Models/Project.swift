import Foundation
import SwiftData

@Model
final class Project: Note {
    @Attribute(.unique) var id: UUID
    var title: String
    var notes: String?
    var isPriority: Bool
    var order: String
    var createdAt: Date

    @Relationship(deleteRule: .nullify, inverse: \Todo.project)
    var todos: [Todo]

    @Relationship(deleteRule: .nullify, inverse: \Event.project)
    var events: [Event]

    @Relationship(deleteRule: .nullify, inverse: \RecurrenceTemplate.project)
    var recurrenceTemplates: [RecurrenceTemplate]

    init(
        id: UUID = UUID(),
        title: String,
        notes: String? = nil,
        isPriority: Bool = false,
        order: String,
        createdAt: Date = .now
    ) {
        self.id = id
        self.title = title
        self.notes = notes
        self.isPriority = isPriority
        self.order = order
        self.createdAt = createdAt
        self.todos = []
        self.events = []
        self.recurrenceTemplates = []
    }

    static func ordered(_ projects: [Project]) -> [Project] {
        projects.sorted {
            if $0.order != $1.order {
                return $0.order < $1.order
            }
            return $0.id.uuidString < $1.id.uuidString
        }
    }
}
