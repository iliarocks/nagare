import Foundation
import SwiftData

/// The exact schema shipped before iCloud sync. Keep this frozen: SwiftData
/// needs the historical shape to migrate existing on-device stores safely.
enum NagareSchemaV1: VersionedSchema {
    static let versionIdentifier = Schema.Version(1, 0, 0)

    static var models: [any PersistentModel.Type] {
        [Project.self, Todo.self, Event.self, RecurrenceTemplate.self]
    }

    @Model
    final class Project {
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
    }

    @Model
    final class Todo {
        @Attribute(.unique) var id: UUID
        var title: String
        var notes: String?
        var scheduledDate: Date
        var completedAt: Date?
        var createdAt: Date
        var order: String
        var projectOrder: String?
        var recurrenceSequence: Int?
        var recurrenceTemplate: RecurrenceTemplate?
        var project: Project?

        init(
            id: UUID = UUID(),
            title: String,
            notes: String? = nil,
            scheduledDate: Date = .now,
            completedAt: Date? = nil,
            createdAt: Date = .now,
            order: String,
            projectOrder: String? = nil
        ) {
            self.id = id
            self.title = title
            self.notes = notes
            self.scheduledDate = scheduledDate
            self.completedAt = completedAt
            self.createdAt = createdAt
            self.order = order
            self.projectOrder = projectOrder
            self.recurrenceSequence = nil
            self.recurrenceTemplate = nil
            self.project = nil
        }
    }

    @Model
    final class Event {
        @Attribute(.unique) var id: UUID
        var title: String
        var notes: String?
        var scheduledDate: Date
        var endDate: Date?
        var calendarIdentifier: String?
        var createdAt: Date
        var order: String
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
            self.order = order
            self.projectOrder = projectOrder
            self.recurrenceSequence = nil
            self.recurrenceTemplate = nil
            self.project = nil
        }
    }

    @Model
    final class RecurrenceTemplate {
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
        var project: Project?

        @Relationship(deleteRule: .nullify, inverse: \Todo.recurrenceTemplate)
        var todoOccurrences: [Todo]

        @Relationship(deleteRule: .nullify, inverse: \Event.recurrenceTemplate)
        var eventOccurrences: [Event]

        init(
            id: UUID = UUID(),
            itemTypeRawValue: String,
            title: String,
            notes: String? = nil,
            modeRawValue: String,
            unitRawValue: String,
            interval: Int,
            anchors: [Int] = [],
            reference: Date? = nil,
            startTimeSeconds: Int? = nil,
            endTimeSeconds: Int? = nil,
            currentItemID: UUID,
            currentSequence: Int = 0,
            createdAt: Date = .now
        ) {
            self.id = id
            self.itemTypeRawValue = itemTypeRawValue
            self.title = title
            self.notes = notes
            self.modeRawValue = modeRawValue
            self.unitRawValue = unitRawValue
            self.interval = interval
            self.anchors = anchors
            self.reference = reference
            self.startTimeSeconds = startTimeSeconds
            self.endTimeSeconds = endTimeSeconds
            self.currentItemID = currentItemID
            self.currentSequence = currentSequence
            self.createdAt = createdAt
            self.project = nil
            self.todoOccurrences = []
            self.eventOccurrences = []
        }
    }
}

/// The first cloud-compatible schema. Its UUIDs remain semantic identities;
/// unlike a database uniqueness constraint, that invariant can be reconciled
/// deterministically after asynchronous CloudKit imports.
enum NagareSchemaV2: VersionedSchema {
    static let versionIdentifier = Schema.Version(2, 0, 0)

    static var models: [any PersistentModel.Type] {
        [Project.self, Todo.self, Event.self, RecurrenceTemplate.self]
    }
}

enum NagareMigrationPlan: SchemaMigrationPlan {
    static var schemas: [any VersionedSchema.Type] {
        [NagareSchemaV1.self, NagareSchemaV2.self]
    }

    static var stages: [MigrationStage] {
        [
            .lightweight(
                fromVersion: NagareSchemaV1.self,
                toVersion: NagareSchemaV2.self
            )
        ]
    }
}

enum NagareSchema {
    static let current = Schema(versionedSchema: NagareSchemaV2.self)
}
