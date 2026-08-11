import Foundation
import SwiftData

@MainActor
enum CalendarImportPersistence {
    static func importPending(
        in context: ModelContext
    ) throws -> [Event] {
        var importedEvents: [Event] = []
        for pendingImport in try PendingCalendarImportStore.pendingImports() {
            let event = try importDraft(pendingImport.draft, in: context)
            try PendingCalendarImportStore.remove(pendingImport)
            importedEvents.append(event)
        }
        return importedEvents
    }

    static func importDraft(
        _ draft: ICalendarEventDraft,
        in context: ModelContext
    ) throws -> Event {
        let sourceIdentifier = draft.sourceIdentifier
        let descriptor = FetchDescriptor<Event>(
            predicate: #Predicate { event in
                event.calendarIdentifier == sourceIdentifier
            }
        )

        if let existing = try context.fetch(descriptor).first {
            existing.title = draft.title
            existing.notes = draft.notes
            existing.scheduledDate = draft.scheduledDate
            existing.endDate = draft.isAllDay ? nil : draft.endDate
            try SwiftDataTransaction.save(context)
            return existing
        }

        let event = Event(
            title: draft.title,
            notes: draft.notes,
            scheduledDate: draft.scheduledDate,
            endDate: draft.isAllDay ? nil : draft.endDate,
            calendarIdentifier: sourceIdentifier,
            order: try ItemOrdering.nextOrder(in: context)
        )
        context.insert(event)
        try SwiftDataTransaction.save(context)
        return event
    }
}
