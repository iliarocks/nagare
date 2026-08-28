import Foundation
import SwiftData

@Model
final class Project: Note, SyncRecord {
    #Index<Project>([\.id])

    @Attribute(.preserveValueOnDeletion) var id: UUID = UUID()
    var title: String = ""
    var notes: String?
    var isPriority: Bool = false
    var priorityRawValue: Int?
    var order: String = ""
    var createdAt: Date = Date.now
    var modifiedAt: Date?
    var syncRecordID: UUID?

    @Relationship(
        deleteRule: .nullify,
        originalName: "todos",
        inverse: \Todo.project
    )
    private var storedTodos: [Todo]?

    @Relationship(
        deleteRule: .nullify,
        originalName: "events",
        inverse: \Event.project
    )
    private var storedEvents: [Event]?

    @Relationship(
        deleteRule: .nullify,
        originalName: "recurrenceTemplates",
        inverse: \RecurrenceTemplate.project
    )
    private var storedRecurrenceTemplates: [RecurrenceTemplate]?

    var todos: [Todo] { storedTodos ?? [] }
    var events: [Event] { storedEvents ?? [] }
    var recurrenceTemplates: [RecurrenceTemplate] {
        storedRecurrenceTemplates ?? []
    }

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
        self.priorityRawValue = ProjectPriority(
            isPriority: isPriority
        ).rawValue
        self.order = order
        self.createdAt = createdAt
        self.modifiedAt = createdAt
        self.syncRecordID = UUID()
        self.storedTodos = []
        self.storedEvents = []
        self.storedRecurrenceTemplates = []
    }

    init(
        id: UUID = UUID(),
        title: String,
        notes: String? = nil,
        priority: ProjectPriority,
        order: String,
        createdAt: Date = .now
    ) {
        self.id = id
        self.title = title
        self.notes = notes
        self.isPriority = priority == .high
        self.priorityRawValue = priority.rawValue
        self.order = order
        self.createdAt = createdAt
        self.modifiedAt = createdAt
        self.syncRecordID = UUID()
        self.storedTodos = []
        self.storedEvents = []
        self.storedRecurrenceTemplates = []
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

extension Project {
    var priority: ProjectPriority {
        get {
            priorityRawValue.flatMap(ProjectPriority.init(rawValue:))
                ?? ProjectPriority(isPriority: isPriority)
        }
        set {
            priorityRawValue = newValue.rawValue
            isPriority = newValue == .high
        }
    }
}
