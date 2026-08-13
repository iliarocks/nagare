import SwiftUI

enum ProjectMoveTarget: Identifiable {
    case item(ItemRecordSnapshot)
    case items([ItemRecordSnapshot])
    case template(RecurrenceTemplateRecordSnapshot)

    var id: String {
        switch self {
        case .item(let item):
            item.id.description
        case .items(let items):
            "items-" + items.map(\.id.description).sorted().joined(separator: ",")
        case .template(let template):
            "template-\(template.id)"
        }
    }

    var projectID: UUID? {
        switch self {
        case .item(let item):
            return item.projectID
        case .items(let items):
            guard let first = items.first?.projectID,
                  items.allSatisfy({ $0.projectID == first }) else {
                return nil
            }
            return first
        case .template(let template):
            return template.projectID
        }
    }

    init(_ item: ItemRecordSnapshot) {
        self = .item(item)
    }
}

struct ProjectMoveEditor: View {
    @Environment(\.dismiss) private var dismiss
    @NagareDataStoreEnvironment private var dataStore

    let target: ProjectMoveTarget

    @State private var errorMessage: String?

    private var projects: [ProjectRecordSnapshot] {
        dataStore.projects
    }

    var body: some View {
        Form {
            Section {
                ProjectPicker(
                    projects: projects,
                    selectedProject: target.projectID.flatMap { projectID in
                        projects.first { $0.id == projectID }
                    },
                    onSelect: move
                )
            }
        }
        .nagareDetailsForm(height: 150)
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

    private func move(to project: ProjectRecordSnapshot?) {
        do {
            switch target {
            case .item(let item):
                try dataStore.assign(.item(item.id), to: project?.id)
            case .items(let items):
                try dataStore.assign(
                    items.map { .item($0.id) },
                    to: project?.id
                )
            case .template(let template):
                try dataStore.assign(
                    .recurrenceTemplate(template.id),
                    to: project?.id
                )
            }
            dismiss()
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}
