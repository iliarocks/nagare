import AppIntents
import OSLog
import SwiftData
import SwiftUI

@main
struct NagareApp: App {
    private enum StartupState {
        case ready(NagareIntentStore)
        case failed
    }

    private static let logger = Logger(
        subsystem: Bundle.main.bundleIdentifier ?? "Nagare",
        category: "Startup"
    )

    private let startupState: StartupState

    init() {
        let arguments = ProcessInfo.processInfo.arguments

        do {
#if DEBUG
            if arguments.contains("--simulate-store-open-failure") {
                throw SimulatedStoreOpenError()
            }
#endif

            let modelContainer = try Self.makeModelContainer(
                arguments: arguments
            )
            try Self.prepareReorderRegressionTestDataIfRequested(
                in: modelContainer.mainContext,
                arguments: arguments
            )
            let intentStore = NagareIntentStore(modelContainer: modelContainer)
            AppDependencyManager.shared.add(dependency: intentStore)
            startupState = .ready(intentStore)
        } catch {
            Self.logger.fault(
                "Unable to open Nagare's data store: \(error.localizedDescription, privacy: .public)"
            )
            startupState = .failed
        }
    }

    var body: some Scene {
        WindowGroup {
            switch startupState {
            case .ready(let intentStore):
                RootView(intentStore: intentStore)
                    .modelContainer(intentStore.modelContainer)
            case .failed:
                StoreStartupFailureView()
            }
        }
    }

    private static func makeModelContainer(
        arguments: [String]
    ) throws -> ModelContainer {
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
                    Project.self,
                    Todo.self,
                    Event.self,
                    RecurrenceTemplate.self
                ]),
                url: storeURL,
                cloudKitDatabase: .none
            )
            return try ModelContainer(
                for: Project.self,
                Todo.self,
                Event.self,
                RecurrenceTemplate.self,
                configurations: configuration
            )
        }

        let schema = Schema([
            Project.self,
            Todo.self,
            Event.self,
            RecurrenceTemplate.self
        ])
        let configuration = ModelConfiguration(
            schema: schema,
            groupContainer: .none,
            cloudKitDatabase: .none
        )
        return try ModelContainer(
            for: schema,
            configurations: configuration
        )
    }

    private static func prepareReorderRegressionTestDataIfRequested(
        in context: ModelContext,
        arguments: [String]
    ) throws {
#if DEBUG
        guard arguments.contains("--reset-and-seed-reorder-ui-test") else {
            return
        }

        for project in try context.fetch(FetchDescriptor<Project>()) {
            context.delete(project)
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

        let priorityProject = Project(
            title: "Priority Project UI",
            notes: "Priority project notes",
            isPriority: true,
            order: "i"
        )
        let backgroundProject = Project(
            title: "Background Project UI",
            notes: "Background project notes",
            order: "i"
        )
        let secondBackgroundProject = Project(
            title: "Background Project Second UI",
            order: "r"
        )
        context.insert(priorityProject)
        context.insert(backgroundProject)
        context.insert(secondBackgroundProject)

        context.insert(Todo(title: "Reorder First", scheduledDate: today, order: "9"))
        context.insert(Todo(title: "Reorder Second", scheduledDate: today, order: "i"))
        context.insert(Todo(title: "Reorder Third", scheduledDate: today, order: "r"))
        context.insert(Todo(title: "Upcoming First", scheduledDate: tomorrow, order: "9"))
        context.insert(Todo(title: "Upcoming Second", scheduledDate: tomorrow, order: "i"))
        context.insert(Todo(title: "Upcoming Third", scheduledDate: tomorrow, order: "r"))
        context.insert(
            Todo(
                title: "Completed Todo UI",
                notes: "Completed item notes",
                scheduledDate: tomorrow,
                completedAt: Calendar.autoupdatingCurrent.date(
                    byAdding: .day,
                    value: -1,
                    to: today
                ) ?? today,
                order: "z"
            )
        )
        context.insert(
            Event(
                title: "Schedule UI Event With A Deliberately Long Title That Wraps Onto Multiple Lines",
                scheduledDate: Calendar.autoupdatingCurrent.date(
                    byAdding: .hour,
                    value: 10,
                    to: today
                ) ?? today,
                order: "w"
            )
        )

        let recurringTodo = Todo(
            title: "Recurring Current UI",
            scheduledDate: today,
            order: "1",
            projectOrder: "i"
        )
        recurringTodo.project = priorityProject
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

#if DEBUG
    private struct SimulatedStoreOpenError: LocalizedError {
        var errorDescription: String? {
            "Simulated store-open failure"
        }
    }
#endif
}

private struct StoreStartupFailureView: View {
    @State private var isShowingError = true

    var body: some View {
        ContentUnavailableView {
            Label(
                "Nagare Couldn't Open Your Items",
                systemImage: "exclamationmark.triangle"
            )
        } description: {
            Text(
                "Your data has not been deleted. Close Nagare and try again. "
                    + "If the problem continues, report error STORE-OPEN-001."
            )
        } actions: {
            Button("Show Error") {
                isShowingError = true
            }
        }
        .accessibilityIdentifier("Store Startup Failure")
        .alert(
            "Nagare Couldn't Open Your Items",
            isPresented: $isShowingError
        ) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(
                "Nagare left your data untouched. Close the app and try again. "
                    + "If it still won't open, report error STORE-OPEN-001."
            )
        }
    }
}
