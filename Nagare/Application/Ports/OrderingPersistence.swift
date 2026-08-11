import Foundation

/// Side-effect boundary consumed by ordering orchestrators.
/// Concrete persistence frameworks live in Infrastructure.
@MainActor
protocol ItemOrderingPersistence: AnyObject {
    func loadItems() throws -> [ItemSnapshot]
    func apply(_ changes: [ItemOrderingChange]) throws
    func applyProjectOrder(_ changes: [ProjectItemOrderingChange]) throws
    func save() throws
    func rollback()
}

@MainActor
protocol ProjectOrderingPersistence: AnyObject {
    func loadProjects() throws -> [ProjectSnapshot]
    func apply(_ changes: [ProjectOrderingChange]) throws
    func save() throws
    func rollback()
}

nonisolated enum OrderingPersistenceError: Error, LocalizedError {
    case loadFailed(String)
    case applyFailed(String)
    case saveFailed(String)

    var errorDescription: String? {
        switch self {
        case .loadFailed(let message):
            "Nagare couldn't read the saved order. \(message)"
        case .applyFailed(let message):
            "Nagare couldn't apply the new order. \(message)"
        case .saveFailed(let message):
            "Nagare couldn't write the new order. \(message)"
        }
    }
}
