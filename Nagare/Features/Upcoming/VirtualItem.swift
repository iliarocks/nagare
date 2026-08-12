import Foundation

struct VirtualItemID: Hashable {
    let templateID: UUID
    let date: Date
}

/// Presentation value that retains the source record only for user actions.
/// Dates, type, and ordering are frozen outputs of the pure projection.
struct VirtualItem: Identifiable {
    let template: RecurrenceTemplate
    let date: Date
    let startDate: Date?
    let endDate: Date?
    let itemType: RecurrenceItemType
    let order: String

    var id: VirtualItemID {
        VirtualItemID(templateID: template.id, date: date)
    }
}

struct VirtualItemProjectionResult {
    let items: [VirtualItem]
    let issues: [RecurrenceProjectionIssue]
}

/// Outer-layer mapper from SwiftData records to immutable projection input and
/// back to presentation values. All date and partial-import decisions remain
/// in `RecurrenceProjectionLogic`.
@MainActor
enum VirtualItemProjection {
    static func input(
        templates: [RecurrenceTemplate],
        todos: [Todo],
        events: [Event]
    ) -> RecurrenceProjectionInput {
        SwiftDataSyncSnapshotMapper.recurrenceProjectionInput(
            templates: templates,
            todos: todos,
            events: events
        )
    }

    static func generate(
        from input: RecurrenceProjectionInput,
        templates: [RecurrenceTemplate],
        starting startDate: Date,
        through horizon: Date,
        calendar: Calendar
    ) -> VirtualItemProjectionResult {
        let projected = RecurrenceProjectionLogic.generate(
            from: input,
            starting: startDate,
            through: horizon,
            calendar: calendar
        )
        let templatesByReference = Dictionary(
            uniqueKeysWithValues: templates.map {
                (
                    SwiftDataSyncSnapshotMapper.reference(
                        for: $0,
                        kind: .recurrenceTemplate
                    ),
                    $0
                )
            }
        )

        return VirtualItemProjectionResult(
            items: projected.items.compactMap { item in
                guard let template = templatesByReference[
                    item.templateReference
                ] else {
                    return nil
                }
                return VirtualItem(
                    template: template,
                    date: item.date,
                    startDate: item.startDate,
                    endDate: item.endDate,
                    itemType: item.itemType,
                    order: item.order
                )
            },
            issues: projected.issues
        )
    }
}

enum UpcomingProjectionError: Error, LocalizedError {
    case horizonCalculationFailed
    case invalidTemplate(RecurrenceProjectionIssue)

    var errorDescription: String? {
        switch self {
        case .horizonCalculationFailed:
            "Nagare couldn't calculate the Upcoming recurrence horizon. (VIRTUAL-006)"
        case .invalidTemplate(let issue):
            "Nagare couldn't project recurrence \(issue.templateID.uuidString). (VIRTUAL-007)"
        }
    }
}
