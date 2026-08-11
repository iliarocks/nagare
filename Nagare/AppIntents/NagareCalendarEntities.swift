import AppIntents
import Foundation
import GeoToolbox

@AppEntity(schema: .calendar.calendar)
struct NagareCalendarEntity: IndexedEntity {
    static let defaultQuery = NagareCalendarQuery()
    static let nagare = NagareCalendarEntity(
        id: "nagare-events",
        title: "Nagare"
    )

    let id: String
    var title: String

    var displayRepresentation: DisplayRepresentation {
        DisplayRepresentation(
            title: "\(title)",
            image: .init(systemName: "calendar")
        )
    }

    init(id: String, title: String) {
        self.id = id
        self.title = title
    }

    struct NagareCalendarQuery: EnumerableEntityQuery, EntityStringQuery {
        func allEntities() async throws -> [NagareCalendarEntity] {
            [.nagare]
        }

        func entities(
            matching string: String
        ) async throws -> [NagareCalendarEntity] {
            NagareCalendarEntity.nagare.title
                .localizedCaseInsensitiveContains(string)
                ? [.nagare]
                : []
        }

        func entities(
            for identifiers: [NagareCalendarEntity.ID]
        ) async throws -> [NagareCalendarEntity] {
            identifiers.contains(NagareCalendarEntity.nagare.id)
                ? [.nagare]
                : []
        }

        func suggestedEntities() async throws -> [NagareCalendarEntity] {
            [.nagare]
        }
    }
}

@AppEnum(schema: .calendar.attendeeStatus)
enum NagareParticipantStatus: String {
    case accepted
    case declined
    case tentative

    static let caseDisplayRepresentations: [Self: DisplayRepresentation] = [
        .accepted: "Accepted",
        .declined: "Declined",
        .tentative: "Tentative"
    ]
}

@AppEnum(schema: .calendar.attendeeType)
enum NagareAttendeeType: String {
    case person

    static let caseDisplayRepresentations: [Self: DisplayRepresentation] = [
        .person: "Person"
    ]
}

@AppEntity(schema: .calendar.attendee)
struct NagareAttendeeEntity: TransientAppEntity {
    var person: IntentPerson
    var status: NagareParticipantStatus?
    var isAttendanceOptional: Bool
    var type: NagareAttendeeType?

    var displayRepresentation: DisplayRepresentation {
        DisplayRepresentation(
            title: "Attendee",
            image: .init(systemName: "person")
        )
    }

    init() {}
}

@AppEnum(schema: .calendar.eventStatus)
enum NagareEventStatus: String {
    case confirmed
    case tentative
    case cancelled

    static let caseDisplayRepresentations: [Self: DisplayRepresentation] = [
        .confirmed: "Confirmed",
        .tentative: "Tentative",
        .cancelled: "Cancelled"
    ]
}

@UnionValue
enum NagareEventLocation {
    case place(PlaceDescriptor)
    case address(String)
}

@UnionValue
enum NagareEventAlarm {
    case duration(Duration)
    case date(Date)
}

@AppEntity(schema: .calendar.event)
struct NagareEventEntity: AppEntity {
    static let defaultQuery = NagareEventQuery()

    let id: UUID
    var calendar: NagareCalendarEntity
    var title: String
    var startDate: Date
    var endDate: Date
    var isAllDay: Bool
    var recurrence: Calendar.RecurrenceRule?
    var note: AttributedString?
    var travelTime: Duration?
    var location: NagareEventLocation?
    var virtualLocation: URL?
    var status: NagareEventStatus?
    var alarms: [NagareEventAlarm]
    var organizers: [IntentPerson]
    var attendees: [NagareAttendeeEntity]
    var isFavorite: Bool

    var displayRepresentation: DisplayRepresentation {
        DisplayRepresentation(
            title: "\(title)",
            subtitle: "\(startDate.formatted(date: .abbreviated, time: .shortened))",
            image: .init(systemName: "calendar")
        )
    }

    init(snapshot: NagareIntentItemSnapshot) {
        self.id = snapshot.id
        self.isFavorite = false
        self.calendar = .nagare
        self.title = snapshot.title
        self.startDate = snapshot.scheduledDate
        self.endDate = snapshot.endDate ?? snapshot.scheduledDate
        self.isAllDay = false
        self.recurrence = nil
        self.note = snapshot.notes.map(AttributedString.init)
        self.travelTime = nil
        self.location = nil
        self.virtualLocation = nil
        self.status = .confirmed
        self.alarms = []
        self.organizers = []
        self.attendees = []
    }

    struct NagareEventQuery: EntityQuery {
        func entities(
            for identifiers: [NagareEventEntity.ID]
        ) async throws -> [NagareEventEntity] {
            []
        }
    }
}
