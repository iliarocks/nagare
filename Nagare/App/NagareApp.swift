import CloudKit
import OSLog
import SwiftData
import SwiftUI
#if os(iOS)
import UIKit
#endif

enum NagareWindowID {
    static let completed = "completed-history"
}

@main
struct NagareApp: App {
    private struct RuntimeState {
        let syncMonitor: SyncIntegrityMonitor
        let cloudSyncMonitor: NagareCloudSyncMonitor
        let dataStore: NagareDataStore
        let cloudSyncEnabled: Bool

        func stop() {
            syncMonitor.stop()
            cloudSyncMonitor.stop()
        }
    }

    private enum StartupState {
        case ready(RuntimeState)
        case failed
    }

    private static let logger = Logger(
        subsystem: Bundle.main.bundleIdentifier ?? "Nagare",
        category: "Startup"
    )

    @State private var startupState: StartupState
    private let arguments: [String]
    private let isRunningUnitTests: Bool

    init() {
#if os(iOS)
        Self.configureMobileNavigationAppearance()
#endif
        let processInfo = ProcessInfo.processInfo
        let arguments = processInfo.arguments
        let isRunningUnitTests = !arguments.contains(
            "--use-reorder-ui-test-store"
        ) && Self.isRunningUnitTests(environment: processInfo.environment)
        self.arguments = arguments
        self.isRunningUnitTests = isRunningUnitTests

        do {
#if DEBUG
            if arguments.contains("--simulate-store-open-failure") {
                throw SimulatedStoreOpenError()
            }
#endif

#if DEBUG
            try NagareCloudSchemaInitializer.runIfRequested(
                arguments,
                schema: NagareSchema.current
            )
#endif
            let cloudSyncEnabled = !isRunningUnitTests
                && NagareCloudPreferences.shouldEnableSync(
                    arguments: arguments
                )
            if cloudSyncEnabled {
                Self.prepareCloudKitRuntime()
            }
            let runtime = try Self.makeRuntimeState(
                arguments: arguments,
                cloudSyncEnabled: cloudSyncEnabled,
                isRunningUnitTests: isRunningUnitTests,
                prepareDevelopmentData: true
            )
            _startupState = State(
                initialValue: .ready(runtime)
            )
        } catch {
            Self.logger.fault(
                "Unable to open Nagare's data store: \(error.localizedDescription, privacy: .public)"
            )
            _startupState = State(initialValue: .failed)
        }
    }

    /// SwiftData cannot change a container's CloudKit configuration in place.
    /// A preference change therefore takes effect the next time Nagare starts,
    /// preserving one CloudKit coordinator per store for the process lifetime.
    private static func makeRuntimeState(
        arguments: [String],
        cloudSyncEnabled: Bool,
        isRunningUnitTests: Bool,
        prepareDevelopmentData: Bool
    ) throws -> RuntimeState {
        let cloudSyncMonitor = NagareCloudSyncMonitor(
            isEnabled: cloudSyncEnabled
        )
        let modelContainer: ModelContainer
        do {
            modelContainer = try makeModelContainer(
                arguments: arguments,
                cloudSyncEnabled: cloudSyncEnabled,
                isRunningUnitTests: isRunningUnitTests
            )
        } catch {
            cloudSyncMonitor.stop()
            throw error
        }
        modelContainer.mainContext.autosaveEnabled = false
        modelContainer.mainContext.author = NagareCloud.localHistoryAuthor
        if prepareDevelopmentData {
            try prepareReorderRegressionTestDataIfRequested(
                in: modelContainer.mainContext,
                arguments: arguments
            )
#if DEBUG
            do {
                try DevelopmentSampleData.seedIfNeeded(
                    in: modelContainer.mainContext,
                    arguments: arguments
                )
            } catch {
                logger.error(
                    "Unable to add development sample data: \(error.localizedDescription, privacy: .public)"
                )
            }
#endif
        }
        _ = try SyncIntegrityRepair.repair(in: modelContainer.mainContext)

        let applicationRepository = SwiftDataNagareRepository(
            modelContainer: modelContainer
        )
        let dataOrchestrator = NagareDataOrchestrator(
            reader: applicationRepository,
            writer: applicationRepository
        )
        let dataStore = try NagareDataStore(
            orchestrator: dataOrchestrator
        )
        let syncMonitor = SyncIntegrityMonitor(
            modelContainer: modelContainer,
            requiresReconciliation: cloudSyncEnabled,
            onPersistedChange: { [dataStore] in
                do {
                    try dataStore.reload()
                } catch {
                    logger.error(
                        "Unable to publish persisted data: \(error.localizedDescription, privacy: .public)"
                    )
                }
            },
            onObservationHealthChanged: { [cloudSyncMonitor] isHealthy, error in
                cloudSyncMonitor.recordHistoryObservation(
                    isHealthy: isHealthy,
                    errorDescription: error
                )
            }
        )
        cloudSyncMonitor.setOnSuccessfulImport { [weak syncMonitor] in
            syncMonitor?.cloudImportDidFinish()
        }
        // Covers an import that may have completed between opening SwiftData's
        // CloudKit stack and attaching the event callback. The debounce also
        // coalesces with any real completion event still in flight.
        syncMonitor.cloudImportDidFinish()
        return RuntimeState(
            syncMonitor: syncMonitor,
            cloudSyncMonitor: cloudSyncMonitor,
            dataStore: dataStore,
            cloudSyncEnabled: cloudSyncEnabled
        )
    }

    private func setCloudSyncEnabled(_ isEnabled: Bool) async throws {
        guard !isRunningUnitTests,
              !arguments.contains("--use-reorder-ui-test-store") else {
            return
        }
        NagareCloudPreferences.setSyncEnabled(isEnabled)
    }

    var body: some Scene {
#if os(macOS)
        WindowGroup {
            startupContent
                .windowFullScreenBehavior(.disabled)
        }
        .defaultSize(width: 800, height: 480)
        .windowToolbarStyle(.unified(showsTitle: false))
        .commands {
            CommandGroup(replacing: .sidebar) {}
            NagareCommands()
        }

        Settings {
            settingsContent
        }
        .windowToolbarStyle(.unified(showsTitle: true))

        Window("Completed", id: NagareWindowID.completed) {
            completedContent
                .windowFullScreenBehavior(.disabled)
        }
        .defaultSize(width: 620, height: 480)
        .windowToolbarStyle(.unified(showsTitle: true))
#else
        WindowGroup {
            startupContent
        }
#endif
    }

    @ViewBuilder
    private var startupContent: some View {
        switch startupState {
        case .ready(let runtime):
            RootView(
                syncMonitor: runtime.syncMonitor,
                cloudSyncEnabledForCurrentLaunch: runtime.cloudSyncEnabled,
                onSetCloudSyncEnabled: setCloudSyncEnabled
            )
                .nagareDataStore(runtime.dataStore)
        case .failed:
            StoreStartupFailureView()
        }
    }

#if os(macOS)
    @ViewBuilder
    private var settingsContent: some View {
        switch startupState {
        case .ready(let runtime):
            NagareSettingsView(
                onSetCloudSyncEnabled: setCloudSyncEnabled
            )
                .nagareDataStore(runtime.dataStore)
        case .failed:
            StoreStartupFailureView()
        }
    }

    @ViewBuilder
    private var completedContent: some View {
        switch startupState {
        case .ready(let runtime):
            CompletedView()
                .nagareDataStore(runtime.dataStore)
        case .failed:
            StoreStartupFailureView()
        }
    }
#endif

    private static func makeModelContainer(
        arguments: [String],
        cloudSyncEnabled: Bool,
        isRunningUnitTests: Bool
    ) throws -> ModelContainer {
        // Hosted tests launch the application before XCTest invokes any test
        // method. Giving that host an isolated store prevents a test run from
        // reading, migrating, syncing, or otherwise depending on developer data.
        if isRunningUnitTests {
            let configuration = ModelConfiguration(
                schema: NagareSchema.current,
                isStoredInMemoryOnly: true,
                cloudKitDatabase: .none
            )
            return try ModelContainer(
                for: NagareSchema.current,
                configurations: configuration
            )
        }

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
                schema: NagareSchema.current,
                url: storeURL,
                cloudKitDatabase: .none
            )
            return try ModelContainer(
                for: NagareSchema.current,
                configurations: configuration
            )
        }

        let configuration: ModelConfiguration
#if DEBUG
        configuration = NagareCloud.configuration(
            schema: NagareSchema.current,
            cloudEnabled: cloudSyncEnabled,
            storeURL: NagareCloud.developmentStoreURL
        )
#else
        configuration = NagareCloud.configuration(
            schema: NagareSchema.current,
            cloudEnabled: cloudSyncEnabled
        )
#endif
        return try ModelContainer(
            for: NagareSchema.current,
            configurations: configuration
        )
    }

    /// SwiftData reaches CloudKit indirectly through Core Data. On macOS,
    /// loading CloudKit before opening the store ensures the app sandbox gains
    /// access to the CloudKit daemon and background activity scheduler.
    @inline(never)
    private static func prepareCloudKitRuntime() {
        print(CKRecord.self)
    }

#if os(iOS)
    private static func configureMobileNavigationAppearance() {
        let tabBar = UITabBar.appearance()
        tabBar.tintColor = .label
        tabBar.unselectedItemTintColor = .secondaryLabel
    }
#endif

    private static func isRunningUnitTests(
        environment: [String: String]
    ) -> Bool {
        // XCTestConfigurationFilePath is set by both Xcode and xcodebuild for
        // hosted unit-test processes. UI-test application processes do not
        // receive it and continue to use their explicitly named test store.
        environment["XCTestConfigurationFilePath"] != nil
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
        ),
        let dayAfterTomorrow = Calendar.autoupdatingCurrent.date(
            byAdding: .day,
            value: 2,
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
                title: "Upcoming Next Day",
                scheduledDate: dayAfterTomorrow,
                order: "i"
            )
        )
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
            Todo(
                title: "Schedule UI Todo With A Deliberately Long Title That Wraps Onto Multiple Lines",
                scheduledDate: Calendar.autoupdatingCurrent.date(
                    byAdding: .hour,
                    value: 10,
                    to: today
                ) ?? today,
                includesTime: true,
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
            reference: today,
            calendar: .autoupdatingCurrent
        )
        let recurringTemplate = try RecurrencePersistence.createTemplate(
            for: recurringTodo,
            rule: dailyRule,
            in: context
        )
        recurringTemplate.title = "Recurring Future UI"
        try SwiftDataTransaction.save(context)
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
