import Foundation

enum NagareWidgetConstants {
#if DEBUG
    static let appGroupIdentifier = "group.ilia.page.nagare.dev"
#else
    static let appGroupIdentifier = "group.ilia.page.nagare"
#endif
    static let todayWidgetKind = "ilia.page.nagare.today-widget"
    static let quickAddWidgetKind = "ilia.page.nagare.quick-add-widget"
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
    var items: [NagareWidgetItem]

    static let empty = NagareWidgetData(items: [])

    func topItem(
        on date: Date,
        calendar: Calendar = .autoupdatingCurrent
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

enum NagareWidgetDataStore {
    private static let dataKey = "today-widget-data"

    static func read() -> NagareWidgetData {
        guard
            let defaults = UserDefaults(
                suiteName: NagareWidgetConstants.appGroupIdentifier
            ),
            let data = defaults.data(forKey: dataKey),
            let value = try? JSONDecoder().decode(
                NagareWidgetData.self,
                from: data
            )
        else {
            return .empty
        }

        return value
    }

    @discardableResult
    static func write(_ value: NagareWidgetData) -> Bool {
        guard
            let defaults = UserDefaults(
                suiteName: NagareWidgetConstants.appGroupIdentifier
            ),
            let data = try? JSONEncoder().encode(value)
        else {
            return false
        }

        defaults.set(data, forKey: dataKey)
        return true
    }
}
