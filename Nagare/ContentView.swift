import SwiftUI
import SwiftData

struct ContentView: View {
    var body: some View {
        NavigationStack {
            TodayView()
        }
    }
}

#Preview {
    ContentView()
        .modelContainer(for: Todo.self, inMemory: true)
}
