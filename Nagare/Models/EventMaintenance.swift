import Foundation
import SwiftData

enum EventMaintenance {
    @MainActor
    static func deletePastEvents(
        in context: ModelContext,
        calendar: Calendar = .autoupdatingCurrent
    ) throws {
        let today = calendar.startOfDay(for: .now)
        let descriptor = FetchDescriptor<Event>(
            predicate: #Predicate { event in
                event.scheduledDate < today
            }
        )

        do {
            for event in try context.fetch(descriptor) {
                context.delete(event)
            }

            if context.hasChanges {
                try context.save()
            }
        } catch {
            context.rollback()
            throw error
        }
    }
}
