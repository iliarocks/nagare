import Foundation
import SwiftData

/// Compatibility facade that translates application/domain errors into the
/// stable project-ordering errors shown by the UI.
@MainActor
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

    static func nextOrder(
        priority: ProjectPriority,
        in context: ModelContext
    ) throws -> String {
        try translateErrors {
            try ProjectOrderingOrchestrator.prepareNextOrder(
                priority: priority,
                using: SwiftDataOrderingAdapter(context: context)
            )
        }
    }

    static func move(
        _ sourceIDs: [UUID],
        toPriority priority: ProjectPriority,
        before destinationID: UUID?,
        in context: ModelContext
    ) throws {
        try translateErrors {
            try ProjectOrderingOrchestrator.move(
                sourceIDs,
                toPriority: priority,
                before: destinationID,
                using: SwiftDataOrderingAdapter(context: context)
            )
        }
    }

    static func saveDisplayedOrder(
        _ projectIDs: [UUID],
        priority: ProjectPriority,
        in context: ModelContext
    ) throws {
        try translateErrors {
            try ProjectOrderingOrchestrator.saveDisplayedOrder(
                projectIDs,
                priority: priority,
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
                throw OrderingError.destinationIsMovingProject
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
