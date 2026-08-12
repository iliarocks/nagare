import Foundation
import SwiftUI

struct ProjectPicker: View {
    let projects: [ProjectRecordSnapshot]
    let selectedProject: ProjectRecordSnapshot?
    let onSelect: (ProjectRecordSnapshot?) -> Void

    private var priorityProjects: [ProjectRecordSnapshot] {
        ordered(projects.filter(\.isPriority))
    }

    private var backgroundProjects: [ProjectRecordSnapshot] {
        ordered(projects.filter { !$0.isPriority })
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

    private func ordered(
        _ projects: [ProjectRecordSnapshot]
    ) -> [ProjectRecordSnapshot] {
        projects.sorted {
            if $0.order != $1.order { return $0.order < $1.order }
            return $0.id.uuidString < $1.id.uuidString
        }
    }
}
