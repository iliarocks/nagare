import Foundation
import SwiftUI

/// Native project-selection actions for an enclosing menu.
struct ProjectMenuActions: View {
    let projects: [ProjectRecordSnapshot]
    let selectedProject: ProjectRecordSnapshot?
    let onSelect: (ProjectRecordSnapshot?) -> Void

    var body: some View {
        Picker("Project", selection: selection) {
            Text("No project")
                .tag(Optional<UUID>.none)

            ForEach(ProjectPriority.displayOrder, id: \.self) { priority in
                ForEach(ordered(projects.filter { $0.priority == priority })) {
                    project in
                    Text(project.title)
                        .tag(Optional(project.id))
                }
            }
        }
        .pickerStyle(.inline)
        .labelsHidden()
    }

    private var selection: Binding<UUID?> {
        Binding(
            get: { selectedProject?.id },
            set: { id in
                onSelect(projects.first { $0.id == id })
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
