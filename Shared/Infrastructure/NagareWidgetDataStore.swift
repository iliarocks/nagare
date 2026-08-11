import Foundation

/// Thin shared-container adapter used by the app and widget extension.
enum NagareWidgetDataStore {
    private static let dataKey = "today-widget-data"

    static func read() -> NagareWidgetData {
        guard
            let defaults = UserDefaults(
                suiteName: NagareAppGroup.identifier
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
                suiteName: NagareAppGroup.identifier
            ),
            let data = try? JSONEncoder().encode(value)
        else {
            return false
        }
        defaults.set(data, forKey: dataKey)
        return true
    }
}
