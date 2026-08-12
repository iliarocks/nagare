import AppIntents
import SwiftData
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

    @Environment(\.modelContext) private var modelContext
    @Environment(\.scenePhase) private var scenePhase
#if os(macOS)
    @Environment(\.openSettings) private var openSystemSettings
#endif

    @Query private var projects: [Project]

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
            NavigationStack {
                CompletedView()
                    .navigationTitle("Completed")
            }
            .presentationDetents([.large])
            .presentationDragIndicator(.visible)
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
            .navigationTitle("Nagare")
            .navigationSplitViewColumnWidth(
                min: 180,
                ideal: 220,
                max: 280
            )
        } detail: {
            Group {
                switch selectedSection {
                case .today:
                    NavigationStack {
                        TodayView(onOpenNotes: openNotes)
                            .navigationTitle("Today")
                            .toolbar { itemToolbar }
                    }
                case .upcoming:
                    NavigationStack {
                        UpcomingView(onOpenNotes: openNotes)
                            .navigationTitle("Upcoming")
                            .toolbar { itemToolbar }
                    }
                case .projects:
                    NavigationStack(path: $projectPath) {
                        ProjectsView(onOpenSettings: openSettings)
                            .navigationTitle("Projects")
                            .navigationDestination(for: UUID.self) { projectID in
                                projectDestination(for: projectID)
                            }
                    }
                }
            }
            .frame(minWidth: 620, minHeight: 480)
        }
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
        }

        ToolbarItem(placement: .nagareTrailing) {
            Button {
                isCreatingItem = true
            } label: {
                Label("New Item", systemImage: "plus")
                    .labelStyle(.iconOnly)
            }
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

    private func openProject(_ project: Project) {
        notesDestination = nil
        selectedSection = .projects
        projectPath = [project.id]
    }

    private func importPendingCalendarEvents() {
        do {
            let events = try CalendarImportPersistence.importPending(
                in: modelContext
            )
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
    let onOpenProject: (Project) -> Void

    init(
        destination: NotesDestination,
        detent: Binding<PresentationDetent>,
        onOpenProject: @escaping (Project) -> Void = { _ in }
    ) {
        self.destination = destination
        _detent = detent
        self.onOpenProject = onOpenProject
    }

    var body: some View {
        notesView
            .presentationDetents(
                [.medium, .large],
                selection: $detent
            )
            .presentationDragIndicator(.visible)
    }

    @ViewBuilder
    private var notesView: some View {
        switch destination {
        case .todo(let todo):
            NotesView(item: todo, onOpenProject: onOpenProject)
        case .event(let event):
            NotesView(item: event, onOpenProject: onOpenProject)
        case .template(let template):
            NotesView(item: template, onOpenProject: onOpenProject)
        }
    }
}

#Preview {
    RootView()
        .modelContainer(
            for: [Project.self, Todo.self, Event.self, RecurrenceTemplate.self],
            inMemory: true
        )
}
