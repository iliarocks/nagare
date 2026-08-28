import SwiftData

/// The storage shape used by every current Nagare build.
///
/// The version remains 4.0.0 so stores that already completed the temporary
/// migration window reopen directly, without another migration pass.
enum NagareCurrentSchema: VersionedSchema {
    static let versionIdentifier = Schema.Version(4, 0, 0)

    static var models: [any PersistentModel.Type] {
        [Project.self, Todo.self, Event.self, RecurrenceTemplate.self]
    }
}

enum NagareSchema {
    static let models = NagareCurrentSchema.models
    static let current = Schema(versionedSchema: NagareCurrentSchema.self)
}
