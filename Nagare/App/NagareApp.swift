import SwiftData
import SwiftUI

@main
struct NagareApp: App {
    private let modelContainer: ModelContainer

    init() {
        do {
            let arguments = ProcessInfo.processInfo.arguments
            if arguments.contains("--use-reorder-ui-test-store") {
                let storeURL = URL.applicationSupportDirectory
                    .appending(path: "reorder-regression.store")
                if arguments.contains("--reset-and-seed-reorder-ui-test") {
                    try? FileManager.default.removeItem(at: storeURL)
                    try? FileManager.default.removeItem(
                        at: URL(filePath: storeURL.path + "-wal")
                    )
                    try? FileManager.default.removeItem(
                        at: URL(filePath: storeURL.path + "-shm")
                    )
                }
                let configuration = ModelConfiguration(
                    "ReorderRegression",
                    schema: Schema([
                        Todo.self,
                        Event.self,
                        RecurrenceTemplate.self
                    ]),
                    url: storeURL
                )
                modelContainer = try ModelContainer(
                    for: Todo.self,
                    Event.self,
                    RecurrenceTemplate.self,
                    configurations: configuration
                )
            } else {
                modelContainer = try ModelContainer(
                    for: Todo.self,
                    Event.self,
                    RecurrenceTemplate.self
                )
            }
            try prepareReorderRegressionTestDataIfRequested(in: modelContainer.mainContext)
        } catch {
            fatalError("Unable to open Nagare's data store: \(error)")
        }
    }

    var body: some Scene {
        WindowGroup {
            RootView()
        }
        .modelContainer(modelContainer)
    }

    private func prepareReorderRegressionTestDataIfRequested(
        in context: ModelContext
    ) throws {
#if DEBUG
        guard ProcessInfo.processInfo.arguments.contains("--reset-and-seed-reorder-ui-test") else {
            return
        }

        for todo in try context.fetch(FetchDescriptor<Todo>()) {
            context.delete(todo)
        }
        for event in try context.fetch(FetchDescriptor<Event>()) {
            context.delete(event)
        }
        for template in try context.fetch(FetchDescriptor<RecurrenceTemplate>()) {
            context.delete(template)
        }

        let today = Calendar.autoupdatingCurrent.startOfDay(for: .now)
        guard let tomorrow = Calendar.autoupdatingCurrent.date(
            byAdding: .day,
            value: 1,
            to: today
        ) else {
            return
        }
        context.insert(Todo(title: "Reorder First", scheduledDate: today, order: "9"))
        context.insert(Todo(title: "Reorder Second", scheduledDate: today, order: "i"))
        context.insert(Todo(title: "Reorder Third", scheduledDate: today, order: "r"))
        context.insert(Todo(title: "Upcoming First", scheduledDate: tomorrow, order: "9"))
        context.insert(Todo(title: "Upcoming Second", scheduledDate: tomorrow, order: "i"))
        context.insert(Todo(title: "Upcoming Third", scheduledDate: tomorrow, order: "r"))

        let recurringTodo = Todo(
            title: "Recurring Current UI",
            scheduledDate: today,
            order: "1"
        )
        context.insert(recurringTodo)
        let dailyRule = try RecurrenceRule.absolute(
            every: 1,
            unit: .day,
            reference: today
        )
        let recurringTemplate = try RecurrencePersistence.createTemplate(
            for: recurringTodo,
            rule: dailyRule,
            in: context
        )
        recurringTemplate.title = "Recurring Future UI"
        try context.save()
#endif
    }
}
