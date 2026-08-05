import Foundation
import SwiftData

enum ProjectOrdering {
    enum OrderingError: LocalizedError {
        case duplicateSource
        case missingSource
        case missingDestination
        case destinationIsMovingProject
        case invalidOrderKey
        case invalidResult
        case saveFailed(String)

        var errorDescription: String? {
            switch self {
            case .duplicateSource:
                "Nagare couldn't move that project because it appeared more than once. (PROJECT-ORDER-001)"
            case .missingSource:
                "Nagare couldn't find a project being moved. (PROJECT-ORDER-002)"
            case .missingDestination:
                "Nagare couldn't find the project drop position. (PROJECT-ORDER-003)"
            case .destinationIsMovingProject:
                "Nagare received an invalid project drop position. (PROJECT-ORDER-004)"
            case .invalidOrderKey:
                "Nagare found an invalid saved project position. (PROJECT-ORDER-005)"
            case .invalidResult:
                "Nagare couldn't verify the new project order. (PROJECT-ORDER-006)"
            case .saveFailed(let message):
                "Nagare couldn't save the project order. \(message) (PROJECT-ORDER-007)"
            }
        }
    }

    @MainActor
    static func nextOrder(
        isPriority: Bool,
        in context: ModelContext
    ) throws -> String {
        let projects = Project.ordered(
            try context.fetch(FetchDescriptor<Project>()).filter {
                $0.isPriority == isPriority
            }
        )
        guard projects.allSatisfy({ FractionalIndex.isValid($0.order) }) else {
            try rebalance(projects)
            return FractionalIndex.between(projects.last?.order, nil) ?? "i"
        }
        if let order = FractionalIndex.between(projects.last?.order, nil) {
            return order
        }
        try rebalance(projects)
        return FractionalIndex.between(projects.last?.order, nil) ?? "i"
    }

    @MainActor
    static func move(
        _ sourceIDs: [UUID],
        toPriority isPriority: Bool,
        before destinationID: UUID?,
        in context: ModelContext
    ) throws {
        let allProjects = try context.fetch(FetchDescriptor<Project>())
        let sourceIDSet = Set(sourceIDs)
        guard sourceIDSet.count == sourceIDs.count else {
            throw OrderingError.duplicateSource
        }

        let projectsByID = Dictionary(
            uniqueKeysWithValues: allProjects.map { ($0.id, $0) }
        )
        let movingProjects = try sourceIDs.map { id in
            guard let project = projectsByID[id] else {
                throw OrderingError.missingSource
            }
            return project
        }
        if let destinationID, sourceIDSet.contains(destinationID) {
            throw OrderingError.destinationIsMovingProject
        }

        let currentDestination = Project.ordered(allProjects.filter {
            $0.isPriority == isPriority
        })
        let remainingDestination = currentDestination.filter {
            !sourceIDSet.contains($0.id)
        }
        guard remainingDestination.allSatisfy({
            FractionalIndex.isValid($0.order)
        }) else {
            throw OrderingError.invalidOrderKey
        }

        let insertionIndex: Int
        if let destinationID {
            guard let index = remainingDestination.firstIndex(where: {
                $0.id == destinationID
            }) else {
                throw OrderingError.missingDestination
            }
            insertionIndex = index
        } else {
            insertionIndex = remainingDestination.endIndex
        }

        var expectedDestination = remainingDestination
        expectedDestination.insert(contentsOf: movingProjects, at: insertionIndex)
        if expectedDestination.map(\.id) == currentDestination.map(\.id),
           movingProjects.allSatisfy({ $0.isPriority == isPriority }) {
            return
        }

        let previousOrder = insertionIndex > remainingDestination.startIndex
            ? remainingDestination[insertionIndex - 1].order
            : nil
        let nextOrder = insertionIndex < remainingDestination.endIndex
            ? remainingDestination[insertionIndex].order
            : nil

        if let keys = FractionalIndex.between(
            count: movingProjects.count,
            previousOrder,
            nextOrder
        ) {
            for (project, key) in zip(movingProjects, keys) {
                project.order = key
            }
        } else {
            try rebalance(expectedDestination)
        }
        for project in movingProjects {
            project.isPriority = isPriority
        }

        let actualDestination = Project.ordered(allProjects.filter {
            $0.isPriority == isPriority
        })
        guard actualDestination.map(\.id) == expectedDestination.map(\.id),
              hasStrictlyIncreasingValidOrders(actualDestination) else {
            throw OrderingError.invalidResult
        }

        do {
            try context.save()
        } catch {
            throw OrderingError.saveFailed(error.localizedDescription)
        }
    }

    @MainActor
    static func saveDisplayedOrder(
        _ projectIDs: [UUID],
        isPriority: Bool,
        in context: ModelContext
    ) throws {
        guard Set(projectIDs).count == projectIDs.count else {
            throw OrderingError.duplicateSource
        }

        let projects = try context.fetch(FetchDescriptor<Project>()).filter {
            $0.isPriority == isPriority
        }
        let projectsByID = Dictionary(
            uniqueKeysWithValues: projects.map { ($0.id, $0) }
        )
        guard projectIDs.count == projects.count,
              Set(projectIDs) == Set(projects.map(\.id)) else {
            throw OrderingError.invalidResult
        }

        let orderedProjects = try projectIDs.map { projectID in
            guard let project = projectsByID[projectID] else {
                throw OrderingError.missingSource
            }
            return project
        }
        try rebalance(orderedProjects)
        guard hasStrictlyIncreasingValidOrders(orderedProjects) else {
            throw OrderingError.invalidResult
        }

        do {
            try context.save()
        } catch {
            throw OrderingError.saveFailed(error.localizedDescription)
        }
    }

    private static func rebalance(_ projects: [Project]) throws {
        let keys = FractionalIndex.rebalancedKeys(count: projects.count)
        guard keys.count == projects.count else {
            throw OrderingError.invalidResult
        }
        for (project, key) in zip(projects, keys) {
            project.order = key
        }
    }

    private static func hasStrictlyIncreasingValidOrders(
        _ projects: [Project]
    ) -> Bool {
        guard projects.allSatisfy({ FractionalIndex.isValid($0.order) }) else {
            return false
        }
        return zip(projects, projects.dropFirst()).allSatisfy {
            $0.order < $1.order
        }
    }
}
