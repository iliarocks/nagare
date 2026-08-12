import SwiftUI

nonisolated private enum ProjectTier: Hashable, Sendable {
    case priority
    case background

    var isPriority: Bool {
        self == .priority
    }
}

nonisolated private struct PersistedProjectProjection: Equatable {
    let priorityIDs: [UUID]
    let backgroundIDs: [UUID]
}

struct ProjectsView: View {
    @NagareDataStoreEnvironment private var dataStore

    @State private var isCreatingProject = false
    @State private var errorMessage: String?
    @State private var displayedPriorityProjectIDs: [UUID]?
    @State private var displayedBackgroundProjectIDs: [UUID]?

    let onOpenSettings: () -> Void

    private var projects: [ProjectRecordSnapshot] {
        dataStore.projects
    }

    init(onOpenSettings: @escaping () -> Void = {}) {
        self.onOpenSettings = onOpenSettings
    }

    private var persistedPriorityProjects: [ProjectRecordSnapshot] {
        ordered(projects.filter(\.isPriority))
    }

    private var persistedBackgroundProjects: [ProjectRecordSnapshot] {
        ordered(projects.filter { !$0.isPriority })
    }

    private var persistedPriorityProjectIDs: [UUID] {
        persistedPriorityProjects.map(\.id)
    }

    private var persistedBackgroundProjectIDs: [UUID] {
        persistedBackgroundProjects.map(\.id)
    }

    private var persistedProjectProjection: PersistedProjectProjection {
        PersistedProjectProjection(
            priorityIDs: persistedPriorityProjectIDs,
            backgroundIDs: persistedBackgroundProjectIDs
        )
    }

    private var priorityProjects: [ProjectRecordSnapshot] {
        displayedProjects(
            persistedPriorityProjects,
            using: displayedPriorityProjectIDs
        )
    }

    private var backgroundProjects: [ProjectRecordSnapshot] {
        displayedProjects(
            persistedBackgroundProjects,
            using: displayedBackgroundProjectIDs
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
                        .nagareToolbarIcon()
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
                        .nagareToolbarIcon()
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
            displayedPriorityProjectIDs = projection.priorityIDs
            displayedBackgroundProjectIDs = projection.backgroundIDs
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
            Section {
                ForEach(priorityProjects) { project in
                    projectRow(project)
                }
                .reorderable(collectionID: ProjectTier.priority)
                .nagareDesktopListRow()
            }

            Section {
                ForEach(backgroundProjects) { project in
                    projectRow(project)
                }
                .reorderable(collectionID: ProjectTier.background)
                .nagareDesktopListRow()
            }
        }
        .nagareListSectionSpacing(.custom(48))
        .reorderContainer(
            for: ProjectRecordSnapshot.self,
            in: ProjectTier.self
        ) {
            reorder($0)
        }
    }

    private func projectRow(_ project: ProjectRecordSnapshot) -> some View {
        NavigationLink(value: project.id) {
            Text(project.title)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.vertical, 4)
        }
        .accessibilityIdentifier("Project \(project.title)")
        .swipeActions(edge: .leading, allowsFullSwipe: false) {
            Button {
                changePriority(of: project)
            } label: {
                Image(
                    systemName: project.isPriority
                        ? "arrow.down"
                        : "arrow.up"
                )
            }
            .accessibilityLabel(
                project.isPriority ? "Deprioritize" : "Prioritize"
            )
            .tint(project.isPriority ? .gray : .blue)
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
            Button {
                changePriority(of: project)
            } label: {
                Label(
                    project.isPriority ? "Deprioritize" : "Prioritize",
                    systemImage: project.isPriority
                        ? "arrow.down"
                        : "arrow.up"
                )
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
        _ difference: ReorderDifference<UUID, ProjectTier>
    ) {
        let tier = difference.destination.collectionID
        let displayedProjectIDs = tier.isPriority
            ? priorityProjects.map(\.id)
            : backgroundProjects.map(\.id)
        guard difference.sources.allSatisfy(displayedProjectIDs.contains) else {
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
        switch difference.destination.position {
        case .before(let id):
            guard let index = displayedProjectIDs.firstIndex(of: id) else {
                return
            }
            destinationOffset = index
        case .end:
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

            setDisplayedProjectIDs(newProjectIDs, for: tier)
            try dataStore.reorderProjects(
                newProjectIDs,
                isPriority: tier.isPriority,
            )
        } catch {
            restoreDisplayedProjectIDs(for: tier)
            errorMessage = error.localizedDescription
        }
    }

    private func displayedProjects(
        _ persistedProjects: [ProjectRecordSnapshot],
        using displayedProjectIDs: [UUID]?
    ) -> [ProjectRecordSnapshot] {
        guard let displayedProjectIDs else {
            return persistedProjects
        }

        let projectsByID = Dictionary(
            uniqueKeysWithValues: projects.map { ($0.id, $0) }
        )
        let projectedProjects = displayedProjectIDs.compactMap {
            projectsByID[$0]
        }
        let allDisplayedIDs = Set(
            (displayedPriorityProjectIDs ?? persistedPriorityProjectIDs)
                + (displayedBackgroundProjectIDs
                    ?? persistedBackgroundProjectIDs)
        )
        return projectedProjects + persistedProjects.filter {
            !allDisplayedIDs.contains($0.id)
        }
    }

    private func setDisplayedProjectIDs(
        _ projectIDs: [UUID],
        for tier: ProjectTier
    ) {
        if tier.isPriority {
            displayedPriorityProjectIDs = projectIDs
        } else {
            displayedBackgroundProjectIDs = projectIDs
        }
    }

    private func restoreDisplayedProjectIDs(for tier: ProjectTier) {
        setDisplayedProjectIDs(
            tier.isPriority
                ? persistedPriorityProjectIDs
                : persistedBackgroundProjectIDs,
            for: tier
        )
    }

    private func changePriority(of project: ProjectRecordSnapshot) {
        let destinationTier: ProjectTier = project.isPriority
            ? .background
            : .priority
        let sourceTier: ProjectTier = project.isPriority
            ? .priority
            : .background
        let sourceProjectIDs = sourceTier.isPriority
            ? priorityProjects.map(\.id)
            : backgroundProjects.map(\.id)
        var destinationProjectIDs = destinationTier.isPriority
            ? priorityProjects.map(\.id)
            : backgroundProjects.map(\.id)
        guard sourceProjectIDs.contains(project.id) else {
            return
        }

        let remainingSourceProjectIDs = sourceProjectIDs.filter {
            $0 != project.id
        }
        destinationProjectIDs.removeAll { $0 == project.id }
        let destinationID: UUID?
        if destinationTier.isPriority {
            destinationProjectIDs.append(project.id)
            destinationID = nil
        } else {
            destinationID = destinationProjectIDs.first
            destinationProjectIDs.insert(project.id, at: 0)
        }

        withAnimation(.smooth) {
            setDisplayedProjectIDs(
                remainingSourceProjectIDs,
                for: sourceTier
            )
            setDisplayedProjectIDs(
                destinationProjectIDs,
                for: destinationTier
            )
        }

        do {
            try dataStore.moveProjects(
                [project.id],
                toPriority: destinationTier.isPriority,
                before: destinationID
            )
        } catch {
            withAnimation(.smooth) {
                restoreDisplayedProjectIDs(for: sourceTier)
                restoreDisplayedProjectIDs(for: destinationTier)
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
