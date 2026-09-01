import SwiftData

/// The storage shape used by every current Nagare build.
///
/// Version 5 adds an optional end date to recurrence templates. Existing
/// templates migrate as indefinitely repeating records.
enum NagareCurrentSchema: VersionedSchema {
    static let versionIdentifier = Schema.Version(5, 0, 0)

    static var models: [any PersistentModel.Type] {
        [Project.self, Todo.self, Event.self, RecurrenceTemplate.self]
    }
}

enum NagareSchema {
    static let models = NagareCurrentSchema.models
    static let current = Schema(versionedSchema: NagareCurrentSchema.self)
}
