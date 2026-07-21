import SwiftUI
import SwiftData

struct ContentView: View {
    private enum Section: Hashable {
        case today
        case upcoming
        case create
    }

    @State private var selectedSection = Section.today
    @State private var isCreatingItem = false

    var body: some View {
        NavigationStack {
            TabView(selection: sectionSelection) {
                Tab(value: Section.today) {
                    TodayView()
                } label: {
                    Label("Today", systemImage: "sun.max")
                        .labelStyle(.iconOnly)
                }

                Tab(value: Section.upcoming) {
                    UpcomingView()
                } label: {
                    Label("Upcoming", systemImage: "calendar")
                        .labelStyle(.iconOnly)
                }

                Tab(value: Section.create, role: .prominent) {
                    EmptyView()
                } label: {
                    Label("New Item", systemImage: "plus")
                        .labelStyle(.iconOnly)
                }
            }
            .sheet(isPresented: $isCreatingItem) {
                ItemFormView()
            }
        }
    }

    private var sectionSelection: Binding<Section> {
        Binding(
            get: { selectedSection },
            set: { section in
                if section == .create {
                    isCreatingItem = true
                } else {
                    selectedSection = section
                }
            }
        )
    }
}

#Preview {
    ContentView()
        .modelContainer(for: [Todo.self, Event.self], inMemory: true)
}
