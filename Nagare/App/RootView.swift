import AppIntents
import SwiftData
import SwiftUI

struct RootView: View {
    private enum Section: Hashable {
        case today
        case upcoming
    }

    @State private var selectedSection = Section.today
    @State private var isCreatingItem = false
    @State private var isShowingCompleted = false
    @State private var notesDestination: NotesDestination?
    @State private var notesDetent: PresentationDetent = .medium

    let intentStore: NagareIntentStore?

    init(intentStore: NagareIntentStore? = nil) {
        self.intentStore = intentStore
    }

    var body: some View {
        NavigationStack {
            TabView(selection: $selectedSection) {
                Tab(value: Section.today) {
                    TodayView(onOpenNotes: openNotes)
                } label: {
                    Label("Today", systemImage: "sun.max")
                        .labelStyle(.iconOnly)
                }

                Tab(value: Section.upcoming) {
                    UpcomingView(onOpenNotes: openNotes)
                } label: {
                    Label("Upcoming", systemImage: "calendar")
                        .labelStyle(.iconOnly)
                }
            }
            .toolbar {
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
                    detent: $notesDetent
                )
                    .id(destination.id)
            }
        }
        .syncTodayWidget()
        .syncNagareSearchIndex(using: intentStore)
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
}

struct NotesSheet: View {
    let destination: NotesDestination
    @Binding var detent: PresentationDetent

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
            NotesView(item: todo)
        case .event(let event):
            NotesView(item: event)
        case .template(let template):
            NotesView(item: template)
        }
    }
}

#Preview {
    RootView()
        .modelContainer(
            for: [Todo.self, Event.self, RecurrenceTemplate.self],
            inMemory: true
        )
}
