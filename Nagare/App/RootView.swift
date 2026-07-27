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
    @State private var notesPath: [NotesDestination] = []

    var body: some View {
        NavigationStack(path: $notesPath) {
            TabView(selection: $selectedSection) {
                Tab(value: Section.today) {
                    TodayView { destination in
                        notesPath.append(destination)
                    }
                } label: {
                    Label("Today", systemImage: "sun.max")
                        .labelStyle(.iconOnly)
                }

                Tab(value: Section.upcoming) {
                    UpcomingView { destination in
                        notesPath.append(destination)
                    }
                } label: {
                    Label("Upcoming", systemImage: "calendar")
                        .labelStyle(.iconOnly)
                }
            }
            .toolbar {
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
            .navigationDestination(for: NotesDestination.self) { destination in
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
        .syncTodayWidget()
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
}

#Preview {
    RootView()
        .modelContainer(
            for: [Todo.self, Event.self, RecurrenceTemplate.self],
            inMemory: true
        )
}
