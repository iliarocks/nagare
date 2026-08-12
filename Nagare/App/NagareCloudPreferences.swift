import Foundation

enum NagareCloudPreferences {
    static let syncEnabledKey = "nagare.iCloudSyncEnabled.v1"

    /// Missing preferences intentionally mean off. Merely installing a build
    /// with CloudKit entitlements must never upload a person's local store.
    static var isSyncEnabled: Bool {
        isSyncEnabled(in: .standard)
    }

    static func isSyncEnabled(in defaults: UserDefaults) -> Bool {
        defaults.bool(forKey: syncEnabledKey)
    }

    static func shouldEnableSync(
        arguments: [String],
        defaults: UserDefaults = .standard
    ) -> Bool {
        !arguments.contains("--use-reorder-ui-test-store")
            && isSyncEnabled(in: defaults)
    }
}
