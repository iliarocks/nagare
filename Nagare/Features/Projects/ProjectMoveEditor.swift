import SwiftData
import SwiftUI

enum ProjectMoveTarget: Identifiable {
    case todo(Todo)
    case event(Event)
    case template(RecurrenceTemplate)

    var id: String {
        switch self {
        case .todo(let todo):
            "todo-\(todo.id)"
        case .event(let event):
            "event-\(event.id)"
        case .template(let template):
            "template-\(template.id)"
        }
    }

    var project: Project? {
        switch self {
        case .todo(let todo):
            todo.project
        case .event(let event):
            event.project
        case .template(let template):
            template.project
        }
    }

    init(_ item: Item) {
        switch item {
        case .todo(let todo):
            self = .todo(todo)
        case .event(let event):
            self = .event(event)
        }
    }
}

struct ProjectMoveEditor: View {
    @Environment(\.modelContext) private var modelContext

    @Query private var projects: [Project]

    let target: ProjectMoveTarget

    @State private var errorMessage: String?

    var body: some View {
        Form {
            Section {
                ProjectPicker(
                    projects: projects,
                    selectedProject: target.project,
                    onSelect: move
                )
            }
        }
        .alert("Project Couldn't Be Changed", isPresented: isShowingError) {
            Button("OK", role: .cancel) {
                errorMessage = nil
            }
        } message: {
            Text(errorMessage ?? "An unknown error occurred.")
        }
    }

    private var isShowingError: Binding<Bool> {
        Binding(
            get: { errorMessage != nil },
            set: { if !$0 { errorMessage = nil } }
        )
    }

    private func move(to project: Project?) {
        do {
            switch target {
            case .todo(let todo):
                try ProjectMembership.assign(
                    .todo(todo),
                    to: project,
                    in: modelContext
                )
            case .event(let event):
                try ProjectMembership.assign(
                    .event(event),
                    to: project,
                    in: modelContext
                )
            case .template(let template):
                try ProjectMembership.assign(
                    template,
                    to: project,
                    in: modelContext
                )
            }
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}
