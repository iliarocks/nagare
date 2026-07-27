import AppIntents

enum NagareAppDestination: String, AppEnum {
    case today
    case quickAdd

    static let typeDisplayRepresentation = TypeDisplayRepresentation(
        name: "Nagare Destination"
    )

    static let caseDisplayRepresentations: [Self: DisplayRepresentation] = [
        .today: "Today",
        .quickAdd: "Quick Add"
    ]
}

struct OpenNagareIntent: OpenIntent, TargetContentProvidingIntent {
    static let title: LocalizedStringResource = "Open Nagare"
    static let description = IntentDescription(
        "Opens a specific part of Nagare."
    )
    static let isDiscoverable = false

    @Parameter(title: "Destination")
    var target: NagareAppDestination

    init() {
        target = .today
    }

    init(target: NagareAppDestination) {
        self.target = target
    }
}
