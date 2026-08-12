import AppIntents
import SwiftUI

struct RootView: View {
    private struct CalendarImportAlert: Identifiable {
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
#endif

    @State private var selectedSection = NavigationSection.today
    @State private var isCreatingItem = false
    @State private var isShowingSettings = false
    @State private var isShowingCompleted = false
    @State private var notesDestination: NotesDestination?
    @State private var notesDetent: PresentationDetent = .medium
    @State private var projectPath: [UUID] = []
    @State private var calendarImportAlert: CalendarImportAlert?

    let intentStore: NagareIntentStore?
    let syncMonitor: SyncIntegrityMonitor?
    let cloudSyncEnabledForCurrentLaunch: Bool

    private var projects: [ProjectRecordSnapshot] {
        dataStore.projects
    }

    init(
        intentStore: NagareIntentStore? = nil,
        syncMonitor: SyncIntegrityMonitor? = nil,
        cloudSyncEnabledForCurrentLaunch: Bool = false
    ) {
        self.intentStore = intentStore
        self.syncMonitor = syncMonitor
        self.cloudSyncEnabledForCurrentLaunch =
            cloudSyncEnabledForCurrentLaunch
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
                    cloudSyncEnabledForCurrentLaunch
            )
        }
        .sheet(isPresented: $isShowingCompleted) {
#if os(macOS)
            CompletedView()
                .frame(width: 620, height: 480)
#else
            NavigationStack {
                CompletedView()
                    .navigationTitle("Completed")
            }
            .nagareSheetDetents([.large])
            .presentationDragIndicator(.visible)
#endif
        }
        .sheet(
            item: $notesDestination,
            onDismiss: resetNotesSheet
        ) { destination in
            NotesSheet(
                destination: destination,
                detent: $notesDetent,
                onOpenProject: openProject
            )
                .id(destination.id)
        }
        .syncTodayWidget()
        .syncNagareIntentContainers(using: intentStore)
        .nagareOnOpenIntent { intent in
            open(intent.target)
        }
        .onOpenURL { url in
            guard let destination = NagareDeepLink.destination(
                for: url
            ) else {
                return
            }
            open(destination)
        }
        .task {
            importPendingCalendarEvents()
        }
        .onChange(of: scenePhase) {
            if scenePhase == .active {
                importPendingCalendarEvents()
                syncMonitor?.repair()
            }
        }
        .alert(item: $calendarImportAlert) { alert in
            Alert(
                title: Text(alert.title),
                message: Text(alert.message),
                dismissButton: .default(Text("OK"))
            )
        }
    }

    @ViewBuilder
    private var rootContent: some View {
#if os(macOS)
        macContent
#else
        mobileContent
#endif
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
                    UpcomingView(onOpenNotes: openNotes)
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
                                ProjectDetailView(project: project)
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
                        UpcomingView(onOpenNotes: openNotes)
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
                createItem: { isCreatingItem = true },
                showCompleted: { isShowingCompleted = true }
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
            Button {
                isCreatingItem = true
            } label: {
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

    private func open(_ destination: NagareAppDestination) {
        switch destination {
        case .today:
            selectedSection = .today
        case .quickAdd:
            selectedSection = .today
            isCreatingItem = true
        }
    }

    private func openNotes(_ destination: NotesDestination) {
        notesDetent = .medium
        notesDestination = destination
    }

    private func resetNotesSheet() {
        notesDetent = .medium
    }

    private func openProject(_ projectID: UUID) {
        notesDestination = nil
        selectedSection = .projects
        projectPath = [projectID]
    }

    private func importPendingCalendarEvents() {
        do {
            let events = try dataStore.importPendingCalendarEvents()
            guard !events.isEmpty else { return }

            let calendar = Calendar.autoupdatingCurrent
            if events.allSatisfy({
                !calendar.isDate($0.scheduledDate, inSameDayAs: .now)
            }) {
                selectedSection = .upcoming
            } else {
                selectedSection = .today
            }

            let message = events.count == 1
                ? "Added \(events[0].title.isEmpty ? "an untitled event" : events[0].title)."
                : "Added \(events.count) calendar events."
            calendarImportAlert = CalendarImportAlert(
                title: events.count == 1
                    ? "Calendar Invite Added"
                    : "Calendar Invites Added",
                message: message
            )
        } catch {
            calendarImportAlert = CalendarImportAlert(
                title: "Calendar Invite Couldn't Be Added",
                message: error.localizedDescription
            )
        }
    }
}

struct NotesSheet: View {
    let destination: NotesDestination
    @Binding var detent: PresentationDetent
    let onOpenProject: (UUID) -> Void

    init(
        destination: NotesDestination,
        detent: Binding<PresentationDetent>,
        onOpenProject: @escaping (UUID) -> Void = { _ in }
    ) {
        self.destination = destination
        _detent = detent
        self.onOpenProject = onOpenProject
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
            onOpenProject: onOpenProject
        )
    }
}

#Preview {
    RootView()
}
