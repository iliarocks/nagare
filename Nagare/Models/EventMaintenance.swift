import Foundation
import SwiftData

enum EventMaintenance {
    @MainActor
    static func deletePastEvents(
        in context: ModelContext,
        calendar: Calendar = .autoupdatingCurrent,
        now: Date = .now
    ) throws {
        let today = calendar.startOfDay(for: now)
        let descriptor = FetchDescriptor<Event>(
            predicate: #Predicate { event in
                event.scheduledDate < today
            }
        )

        let pastEvents = try context.fetch(descriptor)
        try RecurrencePersistence.removePastEventOccurrences(
            pastEvents,
            before: today,
            at: now,
            in: context,
            calendar: calendar
        )
    }
}
