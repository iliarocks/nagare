import SwiftData
import SwiftUI

private struct NagareSearchIndexRevision: Equatable, Hashable {
    struct TodoRevision: Equatable, Hashable {
        let id: UUID
        let title: String
        let notes: String?
        let scheduledDate: Date
        let completedAt: Date?
        let createdAt: Date
        let recurrenceTemplateID: UUID?
    }

    struct EventRevision: Equatable, Hashable {
        let id: UUID
        let title: String
        let notes: String?
        let scheduledDate: Date
        let endDate: Date?
        let createdAt: Date
        let recurrenceTemplateID: UUID?
    }

    struct RecurrenceRevision: Equatable, Hashable {
        let id: UUID
        let mode: String
        let unit: String
        let interval: Int
        let anchors: [Int]
        let reference: Date?
    }

    let todos: [TodoRevision]
    let events: [EventRevision]
    let recurrences: [RecurrenceRevision]
}

private struct NagareSearchIndexSync: ViewModifier {
    @Query private var todos: [Todo]
    @Query private var events: [Event]
    @Query private var recurrenceTemplates: [RecurrenceTemplate]

    let store: NagareIntentStore

    private var revision: NagareSearchIndexRevision {
        NagareSearchIndexRevision(
            todos: todos.map {
                NagareSearchIndexRevision.TodoRevision(
                    id: $0.id,
                    title: $0.title,
                    notes: $0.notes,
                    scheduledDate: $0.scheduledDate,
                    completedAt: $0.completedAt,
                    createdAt: $0.createdAt,
                    recurrenceTemplateID: $0.recurrenceTemplate?.id
                )
            },
            events: events.map {
                NagareSearchIndexRevision.EventRevision(
                    id: $0.id,
                    title: $0.title,
                    notes: $0.notes,
                    scheduledDate: $0.scheduledDate,
                    endDate: $0.endDate,
                    createdAt: $0.createdAt,
                    recurrenceTemplateID: $0.recurrenceTemplate?.id
                )
            },
            recurrences: recurrenceTemplates.map {
                NagareSearchIndexRevision.RecurrenceRevision(
                    id: $0.id,
                    mode: $0.modeRawValue,
                    unit: $0.unitRawValue,
                    interval: $0.interval,
                    anchors: $0.anchors,
                    reference: $0.reference
                )
            }
        )
    }

    func body(content: Content) -> some View {
        content.task(id: revision) {
            try? await Task.sleep(for: .milliseconds(300))
            guard !Task.isCancelled else {
                return
            }
            try? await store.refreshSearchIndex()
        }
    }
}

extension View {
    @ViewBuilder
    func syncNagareSearchIndex(
        using store: NagareIntentStore?
    ) -> some View {
        if let store {
            modifier(NagareSearchIndexSync(store: store))
        } else {
            self
        }
    }
}
