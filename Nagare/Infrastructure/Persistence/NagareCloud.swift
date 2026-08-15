import Foundation
import SwiftData

enum NagareCloud {
    /// One container is shared by iOS and macOS. Development-signed builds use
    /// CloudKit's development environment; App Store builds use production.
    static let containerIdentifier = "iCloud.ilia.page.nagare"

#if DEBUG
    /// Debug builds deliberately avoid SwiftData's `default.store`. Older
    /// development builds used that generic filename, which made stale local
    /// or previously imported development records look like production data.
    static let developmentStoreURL = URL.applicationSupportDirectory
        .appending(path: "NagareDev.store")
#endif

    /// Local transactions carry an author so history consumers can distinguish
    /// Nagare writes from framework-generated/imported transactions if needed.
    static let localHistoryAuthor = "Nagare"

    /// Semantic repairs use a separate context and author so they cannot roll
    /// back an in-progress edit in the UI's context.
    static let reconciliationHistoryAuthor = "Nagare.Reconciliation"

    static func configuration(
        schema: Schema,
        cloudEnabled: Bool,
        storeURL: URL? = nil
    ) -> ModelConfiguration {
        let cloudKitDatabase: ModelConfiguration.CloudKitDatabase =
            cloudEnabled ? .private(containerIdentifier) : .none

        if let storeURL {
            return ModelConfiguration(
                schema: schema,
                url: storeURL,
                cloudKitDatabase: cloudKitDatabase
            )
        }

        return ModelConfiguration(
            schema: schema,
            groupContainer: .none,
            cloudKitDatabase: cloudKitDatabase
        )
    }

}
