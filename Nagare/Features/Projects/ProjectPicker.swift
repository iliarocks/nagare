import Foundation
import SwiftUI

struct ProjectPicker: View {
    let projects: [Project]
    let selectedProject: Project?
    let onSelect: (Project?) -> Void

    private var priorityProjects: [Project] {
        Project.ordered(projects.filter(\.isPriority))
    }

    private var backgroundProjects: [Project] {
        Project.ordered(projects.filter { !$0.isPriority })
    }

    var body: some View {
        Picker("Project", selection: selectedProjectID) {
            Text("No Project")
                .tag(nil as UUID?)

            ForEach(priorityProjects) { project in
                Text(project.title)
                    .tag(Optional(project.id))
            }

            ForEach(backgroundProjects) { project in
                Text(project.title)
                    .tag(Optional(project.id))
            }
        }
        .pickerStyle(.menu)
        .accessibilityIdentifier("Project Picker")
    }

    private var selectedProjectID: Binding<UUID?> {
        Binding(
            get: { selectedProject?.id },
            set: { projectID in
                let project = projectID.flatMap { id in
                    projects.first { $0.id == id }
                }
                onSelect(project)
            }
        )
    }
}
