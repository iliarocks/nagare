import Foundation
import SwiftData

@MainActor
enum TodoMaintenance {
    static func rollUnfinishedTodosForward(
        in context: ModelContext,
        calendar: Calendar = .autoupdatingCurrent,
        now: Date = .now
    ) throws {
        try TodoMaintenanceOrchestrator.rollUnfinishedTodosForward(
            using: SwiftDataOrderingAdapter(context: context),
            calendar: calendar,
            now: now
        )
    }
}
