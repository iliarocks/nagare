import SwiftUI
import WidgetKit

struct TodayWidgetSync: ViewModifier {
    @NagareDataStoreEnvironment private var dataStore

    private var todos: [TodoRecordSnapshot] {
        dataStore.todos
    }

    private var events: [EventRecordSnapshot] {
        dataStore.events
    }

    private var widgetData: NagareWidgetData {
        NagareWidgetData(
            items: todos.compactMap { todo in
                guard todo.completedAt == nil else {
                    return nil
                }

                return NagareWidgetItem(
                    id: "todo-\(todo.id.uuidString)",
                    title: todo.title,
                    kind: .todo,
                    scheduledDate: todo.scheduledDate,
                    endDate: nil,
                    order: todo.order
                )
            } + events.map { event in
                NagareWidgetItem(
                    id: "event-\(event.id.uuidString)",
                    title: event.title,
                    kind: .event,
                    scheduledDate: event.scheduledDate,
                    endDate: event.endDate,
                    order: event.order
                )
            }
        )
    }

    func body(content: Content) -> some View {
        content
            .onChange(of: widgetData, initial: true) { _, newValue in
                guard NagareWidgetDataStore.write(newValue) else {
                    return
                }
                WidgetCenter.shared.reloadTimelines(
                    ofKind: NagareWidgetConstants.todayWidgetKind
                )
            }
    }
}

extension View {
    func syncTodayWidget() -> some View {
        modifier(TodayWidgetSync())
    }
}
