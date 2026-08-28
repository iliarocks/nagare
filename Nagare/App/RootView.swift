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
#if !os(macOS)
    @State private var isShowingCompleted = false
#endif
    @State private var notesDestination: NotesDestination?
    @State private var notesDetent: PresentationDetent = .medium
    @State private var upcomingTargetDate: Date?
    @State private var projectPath: [UUID] = []
    @State private var maintenanceAlert: MaintenanceAlert?
    @State private var lastActiveRefreshAt: Date?

    let syncMonitor: SyncIntegrityMonitor?
    let cloudSyncEnabledForCurrentLaunch: Bool
    let onSetCloudSyncEnabled: (Bool) async throws -> Void

    private var projects: [ProjectRecordSnapshot] {
        dataStore.projects
    }

    init(
        syncMonitor: SyncIntegrityMonitor? = nil,
        cloudSyncEnabledForCurrentLaunch: Bool = false,
        onSetCloudSyncEnabled: @escaping (Bool) async throws -> Void = { _ in }
    ) {
        self.syncMonitor = syncMonitor
        self.cloudSyncEnabledForCurrentLaunch =
            cloudSyncEnabledForCurrentLaunch
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
                cloudSyncEnabledForCurrentLaunch:
                    cloudSyncEnabledForCurrentLaunch,
                onSetCloudSyncEnabled: onSetCloudSyncEnabled
            )
        }
        #if !os(macOS)
        .sheet(isPresented: $isShowingCompleted) {
            NavigationStack {
                CompletedView()
                    .navigationTitle("Completed")
                    .navigationBarTitleDisplayMode(.inline)
            }
            .nagareSheetDetents([.large])
            .presentationDragIndicator(.visible)
        }
        #endif
        .nagareModal(
            item: $notesDestination,
            onDismiss: resetNotesSheet
        ) { destination in
            NotesSheet(
                destination: destination,
                detent: $notesDetent,
                onOpenUpcomingDate: openUpcoming
            )
                .id(destination.id)
        }
        .task { refreshForActiveScene() }
        .onChange(of: scenePhase) {
            if scenePhase == .active {
                refreshForActiveScene()
            }
        }
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
                    TodayView(onOpenNotes: openNotes)
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
                        onOpenNotes: openNotes,
                        scrollTargetDate: $upcomingTargetDate
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
                    ProjectsView(onOpenSettings: openSettings)
                        .navigationDestination(for: UUID.self) { projectID in
                            if let project = projects.first(where: {
                                $0.id == projectID
                            }) {
                                ProjectDetailView(
                                    project: project,
                                    onOpenUpcomingDate: openUpcoming
                                )
                            } else {
                                ContentUnavailableView(
                                    "Project Not Found",
                                    systemImage: "folder.badge.questionmark"
                                )
                            }
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
                        TodayView(onOpenNotes: openNotes)
                            .toolbar { itemToolbar }
                    }
                case .upcoming:
                    NavigationStack {
                        UpcomingView(
                            onOpenNotes: openNotes,
                            scrollTargetDate: $upcomingTargetDate
                        )
                            .toolbar { itemToolbar }
                    }
                case .projects:
                    NavigationStack(path: $projectPath) {
                        ProjectsView(onOpenSettings: openSettings)
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
            ProjectDetailView(
                project: project,
                onOpenUpcomingDate: openUpcoming
            )
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

    private func openUpcoming(_ date: Date) {
        notesDestination = nil
        upcomingTargetDate = Calendar.autoupdatingCurrent.startOfDay(for: date)
        selectedSection = .upcoming
    }

    private func beginManualCreate() {
        isCreatingItem = true
    }

    private func refreshForActiveScene() {
        let now = Date.now
        if let lastActiveRefreshAt,
           now.timeIntervalSince(lastActiveRefreshAt) < 0.5 {
            return
        }
        self.lastActiveRefreshAt = now
        do {
            try dataStore.performMaintenance(at: now)
        } catch {
            maintenanceAlert = MaintenanceAlert(
                title: "Nagare Couldn't Update Today",
                message: error.localizedDescription
            )
        }
        syncMonitor?.applicationDidBecomeActive()
    }
}

struct NotesSheet: View {
    let destination: NotesDestination
    @Binding var detent: PresentationDetent
    let onOpenUpcomingDate: (Date) -> Void

    init(
        destination: NotesDestination,
        detent: Binding<PresentationDetent>,
        onOpenUpcomingDate: @escaping (Date) -> Void = { _ in }
    ) {
        self.destination = destination
        _detent = detent
        self.onOpenUpcomingDate = onOpenUpcomingDate
    }

    var body: some View {
        notesView
            .nagareDocumentSheetFrame()
            .nagareSheetDetents(
                [.medium, .large],
                selection: $detent
            )
            .presentationDragIndicator(.visible)
    }

    @ViewBuilder
    private var notesView: some View {
        NotesView(
            id: destination.recordID,
            onOpenUpcomingDate: onOpenUpcomingDate
        )
    }
}

#Preview {
    RootView()
}
