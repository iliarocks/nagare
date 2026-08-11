import AppIntents
import Foundation
import GeoToolbox

@AppEnum(schema: .reminders.listType)
enum NagareReminderListType: String {
    case standard

    static let caseDisplayRepresentations: [Self: DisplayRepresentation] = [
        .standard: "Standard"
    ]
}

@AppEntity(schema: .reminders.list)
struct NagareReminderListEntity: IndexedEntity {
    static let defaultQuery = NagareReminderListQuery()
    static let nagare = NagareReminderListEntity(
        id: "nagare-todos",
        name: "Nagare",
        type: .standard
    )

    let id: String
    var name: String
    var type: NagareReminderListType

    var displayRepresentation: DisplayRepresentation {
        DisplayRepresentation(
            title: "\(name)",
            image: .init(systemName: "checklist")
        )
    }

    init(id: String, name: String, type: NagareReminderListType) {
        self.id = id
        self.name = name
        self.type = type
    }

    struct NagareReminderListQuery: EnumerableEntityQuery, EntityStringQuery {
        func allEntities() async throws -> [NagareReminderListEntity] {
            [.nagare]
        }

        func entities(
            matching string: String
        ) async throws -> [NagareReminderListEntity] {
            NagareReminderListEntity.nagare.name
                .localizedCaseInsensitiveContains(string)
                ? [.nagare]
                : []
        }

        func entities(
            for identifiers: [NagareReminderListEntity.ID]
        ) async throws -> [NagareReminderListEntity] {
            identifiers.contains(NagareReminderListEntity.nagare.id)
                ? [.nagare]
                : []
        }

        func suggestedEntities() async throws -> [NagareReminderListEntity] {
            [.nagare]
        }
    }
}

@AppEntity(schema: .reminders.section)
struct NagareReminderSectionEntity: AppEntity {
    static let defaultQuery = NagareReminderSectionQuery()

    let id: String
    var name: String
    var list: NagareReminderListEntity

    var displayRepresentation: DisplayRepresentation {
        DisplayRepresentation(title: "\(name)")
    }

    struct NagareReminderSectionQuery: EntityStringQuery {
        func entities(
            for identifiers: [NagareReminderSectionEntity.ID]
        ) async throws -> [NagareReminderSectionEntity] {
            []
        }

        func entities(
            matching string: String
        ) async throws -> [NagareReminderSectionEntity] {
            []
        }
    }
}

@AppEnum(schema: .reminders.locationTriggerEvent)
enum NagareLocationTriggerEvent: String {
    case arrive
    case depart

    static let caseDisplayRepresentations: [Self: DisplayRepresentation] = [
        .arrive: "Arrive",
        .depart: "Depart"
    ]
}

@AppEntity(schema: .reminders.locationTrigger)
struct NagareLocationTriggerEntity: AppEntity {
    static let defaultQuery = NagareLocationTriggerQuery()

    let id: String
    var place: PlaceDescriptor
    var event: NagareLocationTriggerEvent

    var displayRepresentation: DisplayRepresentation {
        DisplayRepresentation(
            title: "Location",
            image: .init(systemName: "location")
        )
    }

    struct NagareLocationTriggerQuery: EntityStringQuery {
        func entities(
            for identifiers: [NagareLocationTriggerEntity.ID]
        ) async throws -> [NagareLocationTriggerEntity] {
            []
        }

        func entities(
            matching string: String
        ) async throws -> [NagareLocationTriggerEntity] {
            []
        }
    }
}

@AppEntity(schema: .reminders.reminder)
struct NagareTodoEntity: AppEntity {
    static let defaultQuery = NagareTodoQuery()

    let id: UUID
    var title: String
    var note: AttributedString?
    var images: [IntentFile]
    var subtasks: [NagareTodoEntity]
    var tags: Set<String>
    var urls: [URL]
    var dueDate: DateComponents?
    var recurrence: Calendar.RecurrenceRule?
    var isCompleted: Bool
    var isFlagged: Bool?
    var creationDate: Date?
    var completionDate: Date?
    var list: NagareReminderListEntity
    var section: NagareReminderSectionEntity?
    var locationTrigger: NagareLocationTriggerEntity?

    var displayRepresentation: DisplayRepresentation {
        let date = dueDate?.date
        return DisplayRepresentation(
            title: "\(title)",
            subtitle: date.map {
                "\($0.formatted(date: .abbreviated, time: .omitted))"
            },
            image: .init(
                systemName: isCompleted ? "checkmark.circle.fill" : "circle"
            )
        )
    }

    init(snapshot: NagareIntentItemSnapshot) {
        self.id = snapshot.id
        self.images = []
        self.subtasks = []
        self.tags = []
        self.urls = []
        self.title = snapshot.title
        self.note = snapshot.notes.map(AttributedString.init)
        self.dueDate = Calendar.autoupdatingCurrent.dateComponents(
            [.calendar, .timeZone, .year, .month, .day],
            from: snapshot.scheduledDate
        )
        self.recurrence = nil
        self.isCompleted = false
        self.isFlagged = nil
        self.creationDate = snapshot.createdAt
        self.completionDate = nil
        self.list = .nagare
        self.section = nil
        self.locationTrigger = nil
    }

    struct NagareTodoQuery: EntityQuery {
        func entities(
            for identifiers: [NagareTodoEntity.ID]
        ) async throws -> [NagareTodoEntity] {
            []
        }
    }
}
