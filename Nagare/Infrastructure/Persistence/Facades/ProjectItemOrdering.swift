import Foundation
import SwiftData

/// Compatibility facade for ordering items inside a project.
@MainActor
enum ProjectItemOrdering {
    enum OrderingError: LocalizedError {
        case duplicateSource
        case missingSource
        case missingDestination
        case destinationIsMovingItem
        case invalidOrderKey
        case invalidResult
        case saveFailed(String)

        var errorDescription: String? {
            switch self {
            case .duplicateSource:
                "Nagare couldn't move that project item because it appeared more than once. (PROJECT-ITEM-ORDER-001)"
            case .missingSource:
                "Nagare couldn't find a project item being moved. (PROJECT-ITEM-ORDER-002)"
            case .missingDestination:
                "Nagare couldn't find the project item drop position. (PROJECT-ITEM-ORDER-003)"
            case .destinationIsMovingItem:
                "Nagare received an invalid project item drop position. (PROJECT-ITEM-ORDER-004)"
            case .invalidOrderKey:
                "Nagare found an invalid saved project item position. (PROJECT-ITEM-ORDER-005)"
            case .invalidResult:
                "Nagare couldn't verify the new project item order. (PROJECT-ITEM-ORDER-006)"
            case .saveFailed(let message):
                "Nagare couldn't save the project item order. \(message) (PROJECT-ITEM-ORDER-007)"
            }
        }
    }

    static func nextOrder(
        in project: Project,
        context: ModelContext
    ) throws -> String {
        try translateErrors {
            try ItemOrderingOrchestrator.prepareNextProjectItemOrder(
                projectID: project.id,
                using: SwiftDataOrderingAdapter(context: context)
            )
        }
    }

    static func move(
        _ sourceIDs: [ItemID],
        before destinationID: ItemID?,
        in project: Project,
        context: ModelContext
    ) throws {
        try translateErrors {
            try ItemOrderingOrchestrator.moveWithinProject(
                sourceIDs,
                before: destinationID,
                projectID: project.id,
                using: SwiftDataOrderingAdapter(context: context)
            )
        }
    }

    private static func translateErrors<Result>(
        _ operation: () throws -> Result
    ) throws -> Result {
        do {
            return try operation()
        } catch let error as OrderingPlanner.PlanningError {
            switch error {
            case .duplicateSource:
                throw OrderingError.duplicateSource
            case .missingSource:
                throw OrderingError.missingSource
            case .missingDestination:
                throw OrderingError.missingDestination
            case .destinationIsMovingValue:
                throw OrderingError.destinationIsMovingItem
            case .invalidOrderKey:
                throw OrderingError.invalidOrderKey
            case .invalidResult:
                throw OrderingError.invalidResult
            }
        } catch let error as OrderingPersistenceError {
            throw OrderingError.saveFailed(error.localizedDescription)
        } catch {
            throw OrderingError.saveFailed(error.localizedDescription)
        }
    }
}
