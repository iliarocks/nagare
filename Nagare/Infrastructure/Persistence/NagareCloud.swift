import Foundation
import SwiftData

enum NagareCloud {
    /// One container is shared by iOS and macOS. Development-signed builds use
    /// CloudKit's development environment; App Store builds use production.
    static let containerIdentifier = "iCloud.ilia.page.nagare"

    /// Local transactions carry an author so history consumers can distinguish
    /// Nagare writes from framework-generated/imported transactions if needed.
    static let localHistoryAuthor = "Nagare"

    static func configuration(
        schema: Schema,
        cloudEnabled: Bool
    ) -> ModelConfiguration {
        ModelConfiguration(
            schema: schema,
            groupContainer: .none,
            cloudKitDatabase: cloudEnabled
                ? .private(containerIdentifier)
                : .none
        )
    }

}
