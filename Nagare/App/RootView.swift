import Combine
import SwiftUI

struct RootView: View {
    private struct MaintenanceAlert: Identifiable {
        let id = UUID()
        let title: String
        let message: String
    }

    private enum NavigationSection: Hashable {
        case today
        case upcoming
        case projects
    }

    @Environment(\.scenePhase) private var scenePhase
    @NagareDataStoreEnvironment private var dataStore
#if os(macOS)
    @Environment(\.openSettings) private var openSystemSettings
    @Environment(\.openWindow) private var openWindow
#endif

    @State private var selectedSection = NavigationSection.today
    @State private var isCreatingItem = false
    @State private var isShowingSettings = false
    @State private var notesDestination: NotesDestination?
    @State private var notesDetent: PresentationDetent = .medium
    @State private var projectPath: [UUID] = []
    @State private var maintenanceAlert: MaintenanceAlert?
    @State private var calendarDay = NagareCalendarDay(now: .now, calendar: .current)
    @State private var dayBoundaryTask: Task<Void, Never>?

    let syncMonitor: SyncIntegrityMonitor?
    let onSetCloudSyncEnabled: (Bool) async throws -> Void

    private var projects: [ProjectRecordSnapshot] {
        dataStore.projects
    }

    init(
        syncMonitor: SyncIntegrityMonitor? = nil,
        onSetCloudSyncEnabled: @escaping (Bool) async throws -> Void = { _ in }
    ) {
        self.syncMonitor = syncMonitor
        self.onSetCloudSyncEnabled = onSetCloudSyncEnabled
    }

    var body: some View {
        rootContent
        .nagareDraftComposer(
            isPresented: $isCreatingItem
        ) {
            CreateView {
                isCreatingItem = false
            }
        }
        .sheet(isPresented: $isShowingSettings) {
            NagareSettingsView(
                onSetCloudSyncEnabled: onSetCloudSyncEnabled
            )
        }
        .nagareModal(
            item: $notesDestination,
            onDismiss: resetNotesSheet
        ) { destination in
            NotesSheet(
                destination: destination,
                detent: $notesDetent
            )
                .id(destination.id)
        }
        .onChange(of: scenePhase, initial: true) {
            if scenePhase == .active {
                refreshForActiveScene()
            } else {
                dayBoundaryTask?.cancel()
            }
        }
        .onReceive(
            NotificationCenter.default.publisher(for: .NSCalendarDayChanged)
                .merge(
                    with: NotificationCenter.default.publisher(for: .NSSystemTimeZoneDidChange),
                    NotificationCenter.default.publisher(for: .NSSystemClockDidChange)
                )
                .receive(on: RunLoop.main)
        ) { _ in
            if scenePhase == .active {
                refreshCalendar()
            }
        }
        .onDisappear { dayBoundaryTask?.cancel() }
        .alert(item: $maintenanceAlert) { alert in
            Alert(
                title: Text(alert.title),
                message: Text(alert.message),
                dismissButton: .default(Text("OK"))
            )
        }
    }

    @ViewBuilder
    private var rootContent: some View {
        Group {
#if os(macOS)
            macContent
#else
            mobileContent
#endif
        }
    }

    private var mobileContent: some View {
        TabView(selection: $selectedSection) {
            Tab(value: NavigationSection.today) {
                NavigationStack {
                    TodayView(calendarDay: calendarDay, onOpenNotes: openNotes)
                        .toolbar {
                            itemToolbar
                        }
                }
            } label: {
                Label("Today", systemImage: "sun.max")
                    .labelStyle(.iconOnly)
            }

            Tab(value: NavigationSection.upcoming) {
                NavigationStack {
                    UpcomingView(
                        calendarDay: calendarDay,
                        onOpenNotes: openNotes
                    )
                        .toolbar {
                            itemToolbar
                        }
                }
            } label: {
                Label("Upcoming", systemImage: "calendar")
                    .labelStyle(.iconOnly)
            }

            Tab(value: NavigationSection.projects) {
                NavigationStack(path: $projectPath) {
                    ProjectsView(
                        onOpenSettings: openSettings,
                        onOpenProject: { projectPath.append($0) }
                    )
                        .navigationDestination(for: UUID.self) { projectID in
                            projectDestination(for: projectID)
                        }
                }
            } label: {
                Label("Projects", systemImage: "folder")
                    .labelStyle(.iconOnly)
            }
        }
    }

#if os(macOS)
    private var macContent: some View {
        NavigationSplitView {
            List(selection: $selectedSection) {
                Label("Today", systemImage: "sun.max")
                    .tag(NavigationSection.today)
                Label("Upcoming", systemImage: "calendar")
                    .tag(NavigationSection.upcoming)
                Label("Projects", systemImage: "folder")
                    .tag(NavigationSection.projects)
            }
            .listStyle(.sidebar)
            .toolbar(removing: .sidebarToggle)
            .navigationSplitViewColumnWidth(
                min: 180,
                ideal: 180,
                max: 180
            )
        } detail: {
            Group {
                switch selectedSection {
                case .today:
                    NavigationStack {
                        TodayView(calendarDay: calendarDay, onOpenNotes: openNotes)
                            .toolbar { itemToolbar }
                    }
                case .upcoming:
                    NavigationStack {
                        UpcomingView(
                            calendarDay: calendarDay,
                            onOpenNotes: openNotes
                        )
                            .toolbar { itemToolbar }
                    }
                case .projects:
                    NavigationStack(path: $projectPath) {
                        ProjectsView(
                            onOpenSettings: openSettings,
                            onOpenProject: { projectPath.append($0) }
                        )
                            .navigationDestination(for: UUID.self) { projectID in
                                projectDestination(for: projectID)
                            }
                    }
                }
            }
            .frame(minWidth: 620, minHeight: 480)
        }
        .navigationSplitViewStyle(.balanced)
        .focusedSceneValue(
            \.nagareCommandActions,
            NagareCommandActions(
                createItem: beginManualCreate,
                showCompleted: {
                    openWindow(id: NagareWindowID.completed)
                },
                showToday: { navigate(to: .today) },
                showUpcoming: { navigate(to: .upcoming) },
                showProjects: { navigate(to: .projects) }
            )
        )
    }
#endif

    @ViewBuilder
    private func projectDestination(for projectID: UUID) -> some View {
        if let project = projects.first(where: { $0.id == projectID }) {
            ProjectDetailView(project: project)
        } else {
            ContentUnavailableView(
                "Project Not Found",
                systemImage: "folder.badge.questionmark"
            )
        }
    }

    @ToolbarContentBuilder
    private var itemToolbar: some ToolbarContent {
        ToolbarItem(placement: .nagareLeading) {
            Button {
                openSettings()
            } label: {
                Label(
                    "Settings",
                    systemImage: "gearshape"
                )
                .labelStyle(.iconOnly)
            }
            .nagareToolbarButton()
        }

#if os(macOS)
        ToolbarSpacer(.flexible)
#endif

        ToolbarItem(placement: .nagareTrailing) {
            Button(action: beginManualCreate) {
                Label("New Item", systemImage: "plus")
                    .labelStyle(.iconOnly)
            }
            .nagareToolbarButton()
        }
    }

    private func openSettings() {
#if os(macOS)
        openSystemSettings()
#else
        isShowingSettings = true
#endif
    }

    private func navigate(to section: NavigationSection) {
        selectedSection = section
        if section == .projects {
            projectPath.removeAll()
        }
    }

    private func openNotes(_ destination: NotesDestination) {
        notesDetent = .medium
        notesDestination = destination
    }

    private func resetNotesSheet() {
        notesDetent = .medium
    }

    private func beginManualCreate() {
        isCreatingItem = true
    }

    private func refreshForActiveScene() {
        refreshCalendar(forceMaintenance: true)
        syncMonitor?.applicationDidBecomeActive()
    }

    private func refreshCalendar(forceMaintenance: Bool = false) {
        let now = Date.now
        let updatedDay = NagareCalendarDay(now: now, calendar: .current)
        if forceMaintenance || updatedDay != calendarDay {
            do {
                try dataStore.performMaintenance(at: now, calendar: updatedDay.calendar)
            } catch {
                maintenanceAlert = MaintenanceAlert(
                    title: "Nagare Couldn't Update Today",
                    message: error.localizedDescription
                )
            }
        }
        calendarDay = updatedDay

        // Reschedule even for a clock change within the same day: sleeping uses
        // elapsed time, while the next midnight follows the system clock.
        dayBoundaryTask?.cancel()
        guard scenePhase == .active, let nextStart = calendarDay.nextStart else { return }
        dayBoundaryTask = Task {
            do {
                try await Task.sleep(for: .seconds(max(0, nextStart.timeIntervalSinceNow)))
            } catch {
                return
            }
            refreshCalendar()
        }
    }
}

struct NotesSheet: View {
    let destination: NotesDestination
    @Binding var detent: PresentationDetent

    var body: some View {
        NotesView(destination: destination)
            .nagareDocumentSheetFrame()
            .nagareSheetDetents(
                [.medium, .large],
                selection: $detent
            )
            .presentationDragIndicator(.visible)
    }

}

#Preview {
    RootView()
}
