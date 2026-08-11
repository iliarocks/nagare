import Foundation

enum NagareWidgetConstants {
    static let todayWidgetKind = "ilia.page.nagare.today-widget"
    static let quickAddControlKind = "ilia.page.nagare.quick-add-control"
}

enum NagareWidgetItemKind: String, Codable, Sendable {
    case todo
    case event
}

struct NagareWidgetItem: Codable, Hashable, Identifiable, Sendable {
    let id: String
    let title: String
    let kind: NagareWidgetItemKind
    let scheduledDate: Date
    let endDate: Date?
    let order: String
}

struct NagareWidgetData: Codable, Equatable, Sendable {
    let items: [NagareWidgetItem]

    static let empty = NagareWidgetData(items: [])

    func topItem(
        on date: Date,
        calendar: Calendar
    ) -> NagareWidgetItem? {
        let today = calendar.startOfDay(for: date)
        guard let tomorrow = calendar.date(
            byAdding: .day,
            value: 1,
            to: today
        ) else {
            return nil
        }

        return items
            .filter { item in
                switch item.kind {
                case .todo:
                    item.scheduledDate < tomorrow
                case .event:
                    item.scheduledDate >= today
                        && item.scheduledDate < tomorrow
                }
            }
            .sorted { first, second in
                if first.order != second.order {
                    return first.order < second.order
                }
                return first.id < second.id
            }
            .first
    }
}
