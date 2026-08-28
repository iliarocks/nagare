import SwiftUI
import WidgetKit

struct TodayWidgetSync: ViewModifier {
    @NagareDataStoreEnvironment private var dataStore

    private var todos: [TodoRecordSnapshot] {
        dataStore.todos
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
                    kind: todo.includesTime ? .timedTodo : .todo,
                    scheduledDate: todo.scheduledDate,
                    endDate: todo.endDate,
                    order: todo.order
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
