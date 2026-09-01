import SwiftUI

nonisolated private struct PersistedProjectProjection: Equatable {
    let idsByPriority: [ProjectPriority: [UUID]]
}

struct ProjectsView: View {
    @NagareDataStoreEnvironment private var dataStore

    @State private var isCreatingProject = false
    @State private var errorMessage: String?
    @State private var displayedProjectIDsByPriority:
        [ProjectPriority: [UUID]] = [:]

    let onOpenSettings: () -> Void

    private var projects: [ProjectRecordSnapshot] {
        dataStore.projects
    }

    init(onOpenSettings: @escaping () -> Void = {}) {
        self.onOpenSettings = onOpenSettings
    }

    private var persistedProjectProjection: PersistedProjectProjection {
        PersistedProjectProjection(
            idsByPriority: Dictionary(
                uniqueKeysWithValues: ProjectPriority.allCases.map {
                    ($0, persistedProjectIDs(for: $0))
                }
            )
        )
    }

    var body: some View {
        Group {
            if projects.isEmpty {
                ContentUnavailableView(
                    "No Projects",
                    systemImage: "folder"
                )
            } else {
                projectList
            }
        }
        .toolbar {
            ToolbarItem(placement: .nagareLeading) {
                Button(action: onOpenSettings) {
                    Label("Settings", systemImage: "gearshape")
                        .labelStyle(.iconOnly)
                }
                .nagareToolbarButton()
            }

#if os(macOS)
            ToolbarSpacer(.flexible)
#endif

            ToolbarItem(placement: .nagareTrailing) {
                Button {
                    isCreatingProject = true
                } label: {
                    Label("New Project", systemImage: "plus")
                        .labelStyle(.iconOnly)
                }
                .nagareToolbarButton()
            }
        }
        .nagareDraftComposer(
            isPresented: $isCreatingProject
        ) {
            ProjectCreateView {
                isCreatingProject = false
            }
        }
        .onChange(of: persistedProjectProjection, initial: true) {
            _, projection in
            displayedProjectIDsByPriority = projection.idsByPriority
        }
        .alert("Nagare Couldn't Save", isPresented: isShowingError) {
            Button("OK", role: .cancel) {
                errorMessage = nil
            }
        } message: {
            Text(errorMessage ?? "An unknown error occurred.")
        }
    }

    private var projectList: some View {
        List {
            ForEach(ProjectPriority.displayOrder, id: \.self) { priority in
                let tierProjects = displayedProjects(for: priority)
                if !tierProjects.isEmpty {
                    Section {
                        ForEach(tierProjects) { project in
                            projectRow(project)
                                .nagareItemListRow()
                        }
                        .reorderable(collectionID: priority)
                        .nagareDesktopItemListRows()
                    }
                }
            }
        }
        .reorderContainer(
            for: ProjectRecordSnapshot.self,
            in: ProjectPriority.self
        ) {
            reorder($0)
        }
    }

    private func projectRow(_ project: ProjectRecordSnapshot) -> some View {
        NavigationLink(value: project.id) {
            Text(project.title)
                .nagareItemTitleFont()
                .fixedSize(horizontal: false, vertical: true)
                .padding(.vertical, 4)
        }
        .accessibilityIdentifier("Project \(project.title)")
        .swipeActions(edge: .leading, allowsFullSwipe: false) {
            if let higher = project.priority.higher {
                Button {
                    changePriority(of: project, to: higher)
                } label: {
                    Image(systemName: "arrow.up")
                }
                .accessibilityLabel("Prioritize")
            }

            if let lower = project.priority.lower {
                Button {
                    changePriority(of: project, to: lower)
                } label: {
                    Image(systemName: "arrow.down")
                }
                .tint(.gray)
                .accessibilityLabel("Deprioritize")
            }
        }
        .swipeActions(edge: .trailing, allowsFullSwipe: true) {
            Button(role: .destructive) {
                delete(project)
            } label: {
                Image(systemName: "trash")
            }
            .accessibilityLabel("Delete")
        }
        .nagareDesktopContextMenu {
            if let higher = project.priority.higher {
                Button {
                    changePriority(of: project, to: higher)
                } label: {
                    Label("Prioritize", systemImage: "arrow.up")
                }
            }

            if let lower = project.priority.lower {
                Button {
                    changePriority(of: project, to: lower)
                } label: {
                    Label("Deprioritize", systemImage: "arrow.down")
                }
            }

            Divider()

            Button(role: .destructive) {
                delete(project)
            } label: {
                Label("Delete", systemImage: "trash")
            }
        }
    }

    private func reorder(
        _ difference: ReorderDifference<UUID, ProjectPriority>
    ) {
        guard !difference.sources.isEmpty else { return }
        let priority = difference.destination.collectionID
        let displayedProjectIDs = displayedProjects(for: priority).map(\.id)
        let destinationID: UUID?
        switch difference.destination.position {
        case .before(let id):
            guard displayedProjectIDs.contains(id) else { return }
            destinationID = id
        case .end:
            destinationID = nil
        }

        let projectsByID = Dictionary(
            uniqueKeysWithValues: projects.map { ($0.id, $0) }
        )
        let sourceProjects = difference.sources.compactMap { projectsByID[$0] }
        guard sourceProjects.count == difference.sources.count else {
            return
        }

        if sourceProjects.contains(where: { $0.priority != priority }) {
            do {
                try dataStore.moveProjects(
                    difference.sources,
                    toPriority: priority,
                    before: destinationID
                )
            } catch {
                errorMessage = error.localizedDescription
            }
            return
        }

        let sourceIDSet = Set(difference.sources)
        let sourceOffsets = IndexSet(
            displayedProjectIDs.indices.filter {
                sourceIDSet.contains(displayedProjectIDs[$0])
            }
        )
        guard sourceOffsets.count == difference.sources.count else {
            return
        }

        let destinationOffset: Int
        if let destinationID {
            guard let index = displayedProjectIDs.firstIndex(
                of: destinationID
            ) else {
                return
            }
            destinationOffset = index
        } else {
            destinationOffset = displayedProjectIDs.endIndex
        }

        do {
            let newProjectIDs = try ReorderProjection.applying(
                sourceOffsets: sourceOffsets,
                toOffset: destinationOffset,
                to: displayedProjectIDs
            )
            guard newProjectIDs != displayedProjectIDs else {
                return
            }

            setDisplayedProjectIDs(newProjectIDs, for: priority)
            try dataStore.reorderProjects(
                newProjectIDs,
                priority: priority,
            )
        } catch {
            restoreDisplayedProjectIDs(for: priority)
            errorMessage = error.localizedDescription
        }
    }

    private func persistedProjects(
        for priority: ProjectPriority
    ) -> [ProjectRecordSnapshot] {
        ordered(projects.filter { $0.priority == priority })
    }

    private func persistedProjectIDs(
        for priority: ProjectPriority
    ) -> [UUID] {
        persistedProjects(for: priority).map(\.id)
    }

    private func displayedProjects(
        for priority: ProjectPriority
    ) -> [ProjectRecordSnapshot] {
        let persistedProjects = persistedProjects(for: priority)
        guard let displayedProjectIDs =
                displayedProjectIDsByPriority[priority] else {
            return persistedProjects
        }

        let projectsByID = Dictionary(
            uniqueKeysWithValues: projects.map { ($0.id, $0) }
        )
        let projectedProjects = displayedProjectIDs.compactMap {
            projectsByID[$0]
        }
        let allDisplayedIDs = Set(ProjectPriority.allCases.flatMap {
            displayedProjectIDsByPriority[$0]
                ?? persistedProjectIDs(for: $0)
        })
        return projectedProjects + persistedProjects.filter {
            !allDisplayedIDs.contains($0.id)
        }
    }

    private func setDisplayedProjectIDs(
        _ projectIDs: [UUID],
        for priority: ProjectPriority
    ) {
        displayedProjectIDsByPriority[priority] = projectIDs
    }

    private func restoreDisplayedProjectIDs(for priority: ProjectPriority) {
        setDisplayedProjectIDs(
            persistedProjectIDs(for: priority),
            for: priority
        )
    }

    private func changePriority(
        of project: ProjectRecordSnapshot,
        to destinationPriority: ProjectPriority
    ) {
        let sourcePriority = project.priority
        guard sourcePriority.higher == destinationPriority
                || sourcePriority.lower == destinationPriority else {
            return
        }
        let sourceProjectIDs = displayedProjects(
            for: sourcePriority
        ).map(\.id)
        var destinationProjectIDs = displayedProjects(
            for: destinationPriority
        ).map(\.id)
        guard sourceProjectIDs.contains(project.id) else {
            return
        }

        let remainingSourceProjectIDs = sourceProjectIDs.filter {
            $0 != project.id
        }
        destinationProjectIDs.removeAll { $0 == project.id }
        let destinationID: UUID?
        if destinationPriority > sourcePriority {
            destinationProjectIDs.append(project.id)
            destinationID = nil
        } else {
            destinationID = destinationProjectIDs.first
            destinationProjectIDs.insert(project.id, at: 0)
        }

        withAnimation(.smooth) {
            setDisplayedProjectIDs(
                remainingSourceProjectIDs,
                for: sourcePriority
            )
            setDisplayedProjectIDs(
                destinationProjectIDs,
                for: destinationPriority
            )
        }

        do {
            try dataStore.moveProjects(
                [project.id],
                toPriority: destinationPriority,
                before: destinationID
            )
        } catch {
            withAnimation(.smooth) {
                restoreDisplayedProjectIDs(for: sourcePriority)
                restoreDisplayedProjectIDs(for: destinationPriority)
            }
            errorMessage = error.localizedDescription
        }
    }

    private func delete(_ project: ProjectRecordSnapshot) {
        do {
            try dataStore.deleteProject(project.id)
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func ordered(
        _ projects: [ProjectRecordSnapshot]
    ) -> [ProjectRecordSnapshot] {
        projects.sorted {
            if $0.order != $1.order { return $0.order < $1.order }
            return $0.id.uuidString < $1.id.uuidString
        }
    }

    private var isShowingError: Binding<Bool> {
        Binding(
            get: { errorMessage != nil },
            set: { if !$0 { errorMessage = nil } }
        )
    }
}
