import AppIntents
import SwiftData
import SwiftUI

struct RootView: View {
    private struct CalendarImportAlert: Identifiable {
        let id = UUID()
        let title: String
        let message: String
    }

    private enum Section: Hashable {
        case today
        case upcoming
        case projects
    }

    @Environment(\.modelContext) private var modelContext
    @Environment(\.scenePhase) private var scenePhase

    @Query private var projects: [Project]

    @State private var selectedSection = Section.today
    @State private var isCreatingItem = false
    @State private var isShowingCompleted = false
    @State private var notesDestination: NotesDestination?
    @State private var notesDetent: PresentationDetent = .medium
    @State private var projectPath: [UUID] = []
    @State private var calendarImportAlert: CalendarImportAlert?

    let intentStore: NagareIntentStore?

    init(intentStore: NagareIntentStore? = nil) {
        self.intentStore = intentStore
    }

    var body: some View {
        TabView(selection: $selectedSection) {
            Tab(value: Section.today) {
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

            Tab(value: Section.upcoming) {
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

            Tab(value: Section.projects) {
                NavigationStack(path: $projectPath) {
                    ProjectsView()
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
        .sheet(isPresented: $isCreatingItem) {
            CreateView()
        }
        .sheet(isPresented: $isShowingCompleted) {
            NavigationStack {
                CompletedView()
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
        .onAppIntentExecution(OpenNagareIntent.self) { intent in
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

    @ToolbarContentBuilder
    private var itemToolbar: some ToolbarContent {
        ToolbarItem(placement: .topBarLeading) {
            Button {
                isShowingCompleted = true
            } label: {
                Label(
                    "Completed",
                    systemImage: "clock.arrow.circlepath"
                )
                .labelStyle(.iconOnly)
            }
        }

        ToolbarItem(placement: .topBarTrailing) {
            Button {
                isCreatingItem = true
            } label: {
                Label("New Item", systemImage: "plus")
                    .labelStyle(.iconOnly)
            }
        }
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
