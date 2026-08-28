import Foundation

struct VirtualItemID: Hashable {
    let templateID: UUID
    let date: Date
}

struct VirtualItem: Identifiable {
    let template: RecurrenceTemplateRecordSnapshot
    let date: Date
    let startDate: Date?
    let endDate: Date?
    let order: String

    var id: VirtualItemID {
        VirtualItemID(templateID: template.id, date: date)
    }
}

struct VirtualItemProjectionResult {
    let items: [VirtualItem]
    let issues: [RecurrenceProjectionIssue]
}

enum VirtualItemProjection {
    static func generate(
        from input: RecurrenceProjectionInput,
        templates: [RecurrenceTemplateRecordSnapshot],
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
        let templatesByID = Dictionary(
            uniqueKeysWithValues: templates.map { ($0.id, $0) }
        )

        return VirtualItemProjectionResult(
            items: projected.items.compactMap { item in
                guard let template = templatesByID[item.templateID] else {
                    return nil
                }
                return VirtualItem(
                    template: template,
                    date: item.date,
                    startDate: item.startDate,
                    endDate: item.endDate,
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
