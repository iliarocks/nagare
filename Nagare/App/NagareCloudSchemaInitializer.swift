#if DEBUG
import CoreData
import Foundation
import SwiftData

/// An explicit development operation, kept at the app boundary because the
/// normal persistence adapter must not depend on Core Data implementation
/// details. It never opens Nagare's real local store.
enum NagareCloudSchemaInitializer {
    static func runIfRequested(
        _ arguments: [String],
        schema: Schema
    ) throws {
        guard arguments.contains("--initialize-cloudkit-schema") else {
            return
        }

        let storeURL = FileManager.default.temporaryDirectory
            .appending(path: "NagareCloudSchema-\(UUID().uuidString).store")
        defer { removeStoreFiles(at: storeURL) }

        try autoreleasepool {
            guard let managedModel = NSManagedObjectModel
                .makeManagedObjectModel(for: schema) else {
                throw NagareCloudSchemaError.unableToCreateManagedObjectModel
            }

            let description = NSPersistentStoreDescription(url: storeURL)
            description.cloudKitContainerOptions =
                NSPersistentCloudKitContainerOptions(
                    containerIdentifier: NagareCloud.containerIdentifier
                )
            description.shouldAddStoreAsynchronously = false

            let container = NSPersistentCloudKitContainer(
                name: "NagareCloudSchema",
                managedObjectModel: managedModel
            )
            container.persistentStoreDescriptions = [description]

            var loadError: Error?
            container.loadPersistentStores { _, error in
                loadError = error
            }
            if let loadError { throw loadError }

            defer {
                for store in container.persistentStoreCoordinator
                    .persistentStores {
                    try? container.persistentStoreCoordinator.remove(store)
                }
            }

            try container.initializeCloudKitSchema()
        }
    }

    private static func removeStoreFiles(at url: URL) {
        for suffix in ["", "-wal", "-shm"] {
            try? FileManager.default.removeItem(
                at: URL(filePath: url.path + suffix)
            )
        }
    }
}

private enum NagareCloudSchemaError: LocalizedError {
    case unableToCreateManagedObjectModel

    var errorDescription: String? {
        switch self {
        case .unableToCreateManagedObjectModel:
            "Unable to derive the CloudKit schema from Nagare's SwiftData model."
        }
    }
}
#endif
