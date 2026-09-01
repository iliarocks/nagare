import Foundation

/// A portable, versioned representation of every user-owned Nagare record.
/// CloudKit physical identities are deliberately absent.
nonisolated struct NagareDataArchive: Codable, Equatable, Sendable {
    static let currentFormatVersion = 2

    let formatVersion: Int
    let exportedAt: Date
    let projects: [NagareArchiveProject]
    let todos: [NagareArchiveTodo]
    let recurrenceTemplates: [NagareArchiveRecurrenceTemplate]

    init(snapshot: NagareDataSnapshot, exportedAt: Date) {
        formatVersion = Self.currentFormatVersion
        self.exportedAt = exportedAt
        projects = snapshot.canonicalProjects.map(NagareArchiveProject.init)
        todos = snapshot.canonicalTodos.map(NagareArchiveTodo.init)
        recurrenceTemplates = snapshot.canonicalRecurrenceTemplates.map(
            NagareArchiveRecurrenceTemplate.init
        )
    }

    init(
        formatVersion: Int = Self.currentFormatVersion,
        exportedAt: Date,
        projects: [NagareArchiveProject],
        todos: [NagareArchiveTodo],
        recurrenceTemplates: [NagareArchiveRecurrenceTemplate]
    ) {
        self.formatVersion = formatVersion
        self.exportedAt = exportedAt
        self.projects = projects
        self.todos = todos
        self.recurrenceTemplates = recurrenceTemplates
    }
}

nonisolated struct NagareArchiveProject: Codable, Equatable, Sendable {
    let id: UUID
    let createdAt: Date
    let title: String
    let notes: String?
    let isPriority: Bool
    let priorityRawValue: Int?
    let order: String

    var priority: ProjectPriority {
        priorityRawValue.flatMap(ProjectPriority.init(rawValue:))
            ?? ProjectPriority(isPriority: isPriority)
    }

    init(_ project: ProjectRecordSnapshot) {
        id = project.id
        createdAt = project.createdAt
        title = project.title
        notes = project.notes
        isPriority = project.isPriority
        priorityRawValue = project.priority.rawValue
        order = project.order
    }

    init(
        id: UUID,
        createdAt: Date,
        title: String,
        notes: String?,
        isPriority: Bool,
        priority: ProjectPriority? = nil,
        order: String
    ) {
        self.id = id
        self.createdAt = createdAt
        self.title = title
        self.notes = notes
        self.isPriority = isPriority
        self.priorityRawValue = priority?.rawValue
        self.order = order
    }
}

nonisolated struct NagareArchiveTodo: Codable, Equatable, Sendable {
    let id: UUID
    let createdAt: Date
    let title: String
    let notes: String?
    let scheduledDate: Date
    let includesTime: Bool
    let endDate: Date?
    let calendarIdentifier: String?
    let completedAt: Date?
    let order: String
    let projectOrder: String?
    let recurrenceSequence: Int?
    let recurrenceTemplateID: UUID?
    let projectID: UUID?

    init(_ todo: TodoRecordSnapshot) {
        id = todo.id
        createdAt = todo.createdAt
        title = todo.title
        notes = todo.notes
        scheduledDate = todo.scheduledDate
        includesTime = todo.includesTime
        endDate = todo.endDate
        calendarIdentifier = todo.calendarIdentifier
        completedAt = todo.completedAt
        order = todo.order
        projectOrder = todo.projectOrder
        recurrenceSequence = todo.recurrenceSequence
        recurrenceTemplateID = todo.recurrenceTemplateID
        projectID = todo.projectID
    }

    init(
        id: UUID,
        createdAt: Date,
        title: String,
        notes: String?,
        scheduledDate: Date,
        includesTime: Bool = false,
        endDate: Date? = nil,
        calendarIdentifier: String? = nil,
        completedAt: Date?,
        order: String,
        projectOrder: String?,
        recurrenceSequence: Int?,
        recurrenceTemplateID: UUID?,
        projectID: UUID?
    ) {
        self.id = id
        self.createdAt = createdAt
        self.title = title
        self.notes = notes
        self.scheduledDate = scheduledDate
        self.includesTime = includesTime
        self.endDate = includesTime ? endDate : nil
        self.calendarIdentifier = calendarIdentifier
        self.completedAt = completedAt
        self.order = order
        self.projectOrder = projectOrder
        self.recurrenceSequence = recurrenceSequence
        self.recurrenceTemplateID = recurrenceTemplateID
        self.projectID = projectID
    }
}

nonisolated struct NagareArchiveRecurrenceTemplate:
    Codable,
    Equatable,
    Sendable
{
    let id: UUID
    let createdAt: Date
    let title: String
    let notes: String?
    let modeRawValue: String
    let unitRawValue: String
    let interval: Int
    let anchors: [Int]
    let reference: Date?
    let repeatUntil: Date?
    let startTimeSeconds: Int?
    let endTimeSeconds: Int?
    let currentItemID: UUID
    let currentSequence: Int
    let projectID: UUID?

    init(_ template: RecurrenceTemplateRecordSnapshot) {
        id = template.id
        createdAt = template.createdAt
        title = template.title
        notes = template.notes
        modeRawValue = template.modeRawValue
        unitRawValue = template.unitRawValue
        interval = template.interval
        anchors = template.anchors
        reference = template.reference
        repeatUntil = template.repeatUntil
        startTimeSeconds = template.startTimeSeconds
        endTimeSeconds = template.endTimeSeconds
        currentItemID = template.currentItemID
        currentSequence = template.currentSequence
        projectID = template.projectID
    }

    init(
        id: UUID,
        createdAt: Date,
        title: String,
        notes: String?,
        modeRawValue: String,
        unitRawValue: String,
        interval: Int,
        anchors: [Int],
        reference: Date?,
        repeatUntil: Date? = nil,
        startTimeSeconds: Int?,
        endTimeSeconds: Int?,
        currentItemID: UUID,
        currentSequence: Int,
        projectID: UUID?
    ) {
        self.id = id
        self.createdAt = createdAt
        self.title = title
        self.notes = notes
        self.modeRawValue = modeRawValue
        self.unitRawValue = unitRawValue
        self.interval = interval
        self.anchors = anchors
        self.reference = reference
        self.repeatUntil = repeatUntil
        self.startTimeSeconds = startTimeSeconds
        self.endTimeSeconds = endTimeSeconds
        self.currentItemID = currentItemID
        self.currentSequence = currentSequence
        self.projectID = projectID
    }
}

nonisolated struct NagareDataImportTemplate: Sendable {
    let record: NagareArchiveRecurrenceTemplate
    let rule: RecurrenceRule
}

nonisolated struct NagareDataImportSummary: Equatable, Sendable {
    let projectCount: Int
    let todoCount: Int
    let recurrenceCount: Int
    let createdCount: Int
    let updatedCount: Int

    var totalCount: Int {
        projectCount + todoCount + recurrenceCount
    }
}

nonisolated struct NagareDataImportPlan: Sendable {
    let projects: [NagareArchiveProject]
    let todos: [NagareArchiveTodo]
    let recurrenceTemplates: [NagareDataImportTemplate]
    let summary: NagareDataImportSummary
}
