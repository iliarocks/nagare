import AppIntents
import Foundation

enum NagareListItemKind: String, AppEnum {
    case todo
    case event

    static let typeDisplayRepresentation = TypeDisplayRepresentation(
        name: "Nagare Item Type"
    )

    static let caseDisplayRepresentations: [Self: DisplayRepresentation] = [
        .todo: "Todo",
        .event: "Event"
    ]
}

struct NagareListItemEntity: AppEntity {
    static let typeDisplayRepresentation = TypeDisplayRepresentation(
        name: "Nagare Item"
    )
    static let defaultQuery = NagareListItemQuery()

    let id: String
    let modelID: UUID
    let kind: NagareListItemKind
    let title: String
    let scheduledDate: Date
    let endDate: Date?

    var displayRepresentation: DisplayRepresentation {
        let subtitle: String = switch kind {
        case .todo:
            scheduledDate.formatted(date: .abbreviated, time: .omitted)
        case .event:
            scheduledDate.formatted(date: .abbreviated, time: .shortened)
        }
        return DisplayRepresentation(
            title: "\(title)",
            subtitle: "\(subtitle)",
            image: .init(systemName: kind == .todo ? "circle" : "calendar")
        )
    }

    init(snapshot: NagareIntentItemSnapshot) {
        self.modelID = snapshot.id
        self.kind = snapshot.kind == .todo ? .todo : .event
        self.id = "\(self.kind.rawValue):\(snapshot.id.uuidString)"
        self.title = snapshot.title
        self.scheduledDate = snapshot.scheduledDate
        self.endDate = snapshot.endDate
    }

    struct NagareListItemQuery: EnumerableEntityQuery, EntityStringQuery {
        @Dependency var store: NagareIntentStore

        @MainActor
        func allEntities() async throws -> [NagareListItemEntity] {
            try store.todayItemSnapshots().map(NagareListItemEntity.init)
        }

        @MainActor
        func entities(
            matching string: String
        ) async throws -> [NagareListItemEntity] {
            try store.todayItemSnapshots()
                .filter { $0.title.localizedCaseInsensitiveContains(string) }
                .map(NagareListItemEntity.init)
        }

        @MainActor
        func entities(
            for identifiers: [NagareListItemEntity.ID]
        ) async throws -> [NagareListItemEntity] {
            let identifierSet = Set(identifiers)
            return try store.todayItemSnapshots()
                .map(NagareListItemEntity.init)
                .filter { identifierSet.contains($0.id) }
        }

        @MainActor
        func suggestedEntities() async throws -> [NagareListItemEntity] {
            try store.todayItemSnapshots().map(NagareListItemEntity.init)
        }
    }
}

struct GetNextNagareItemIntent: AppIntent {
    static let title: LocalizedStringResource = "What's Next"
    static let description = IntentDescription(
        "Gets the first item in Nagare's Today order."
    )
    static let openAppWhenRun = false

    @Dependency var store: NagareIntentStore

    @MainActor
    func perform() async throws -> some ReturnsValue<NagareListItemEntity?> & ProvidesDialog {
        let next = try store.todayItemSnapshots().first.map(
            NagareListItemEntity.init
        )
        let dialog = next.map(NagareIntentDialog.next) ?? "Nothing is on your Today list."
        return .result(value: next, dialog: "\(dialog)")
    }
}

struct GetItemAfterNagareItemIntent: AppIntent {
    static let title: LocalizedStringResource = "What Comes After"
    static let description = IntentDescription(
        "Gets the item after another item in Nagare's Today order."
    )
    static let openAppWhenRun = false

    @Parameter(title: "Today's Item")
    var item: NagareListItemEntity

    @Dependency var store: NagareIntentStore

    static var parameterSummary: some ParameterSummary {
        Summary("What comes after \(\.$item) on Today")
    }

    @MainActor
    func perform() async throws -> some ReturnsValue<NagareListItemEntity?> & ProvidesDialog {
        let items = try store.todayItemSnapshots().map(NagareListItemEntity.init)
        guard let index = items.firstIndex(where: { $0.id == item.id }) else {
            throw NagareIntentError.itemNotOnToday
        }

        let nextIndex = items.index(after: index)
        let next = items.indices.contains(nextIndex) ? items[nextIndex] : nil
        let dialog = next.map(NagareIntentDialog.after)
            ?? "Nothing comes after \(item.title) on Today."
        return .result(value: next, dialog: "\(dialog)")
    }
}

struct GetTodaysNagareEventsIntent: AppIntent {
    static let title: LocalizedStringResource = "Today's Events"
    static let description = IntentDescription(
        "Gets the Events scheduled in Nagare today."
    )
    static let openAppWhenRun = false

    @Dependency var store: NagareIntentStore

    @MainActor
    func perform() async throws -> some ReturnsValue<[NagareEventEntity]> & ProvidesDialog {
        let events = try store.todayEventSnapshots().map(NagareEventEntity.init)
        return .result(
            value: events,
            dialog: "\(NagareIntentDialog.events(events))"
        )
    }
}

struct NagareAppShortcuts: AppShortcutsProvider {
    static var appShortcuts: [AppShortcut] {
        AppShortcut(
            intent: GetNextNagareItemIntent(),
            phrases: [
                "What's next in \(.applicationName)",
                "What is next in \(.applicationName)"
            ],
            shortTitle: "What's Next",
            systemImageName: "arrow.right.circle"
        )

        AppShortcut(
            intent: GetItemAfterNagareItemIntent(),
            phrases: [
                "What comes after \(\.$item) in \(.applicationName)",
                "What's after \(\.$item) in \(.applicationName)"
            ],
            shortTitle: "What Comes After",
            systemImageName: "arrow.right.to.line"
        )

        AppShortcut(
            intent: GetTodaysNagareEventsIntent(),
            phrases: [
                "What Events do I have today in \(.applicationName)",
                "Show today's Events in \(.applicationName)"
            ],
            shortTitle: "Today's Events",
            systemImageName: "calendar"
        )

    }

    static let shortcutTileColor: ShortcutTileColor = .blue
}

@MainActor
private enum NagareIntentDialog {
    static func next(_ item: NagareListItemEntity) -> String {
        switch item.kind {
        case .todo:
            "Next is the Todo \(item.title)."
        case .event:
            "Next is \(item.title) at \(item.scheduledDate.formatted(date: .omitted, time: .shortened))."
        }
    }

    static func after(_ item: NagareListItemEntity) -> String {
        switch item.kind {
        case .todo:
            "After that is the Todo \(item.title)."
        case .event:
            "After that is \(item.title) at \(item.scheduledDate.formatted(date: .omitted, time: .shortened))."
        }
    }

    static func events(_ events: [NagareEventEntity]) -> String {
        switch events.count {
        case 0:
            "You have no Events in Nagare today."
        case 1:
            "You have one Event today: \(eventDescription(events[0]))."
        default:
            "You have \(events.count) Events today: "
                + events.map(eventDescription).joined(separator: ", ")
                + "."
        }
    }

    private static func eventDescription(_ event: NagareEventEntity) -> String {
        "\(event.title) at \(event.startDate.formatted(date: .omitted, time: .shortened))"
    }
}
