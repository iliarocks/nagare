import Foundation

enum NagareCloudPreferences {
#if DEBUG
    /// Debug has its own preference generation so a stale development setting
    /// cannot attach a newly isolated sample store to CloudKit on first launch.
    static let syncEnabledKey = "nagare.iCloudSyncEnabled.debug.v1"
#else
    static let syncEnabledKey = "nagare.iCloudSyncEnabled.v1"
#endif

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
