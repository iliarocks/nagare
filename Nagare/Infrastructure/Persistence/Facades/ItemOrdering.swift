import Foundation
import SwiftData

/// Compatibility facade for UI callers. SwiftData is confined to the adapter;
/// orchestration and ordering decisions live in their dedicated layers.
@MainActor
enum ItemOrdering {
    enum MoveError: LocalizedError {
        case duplicateSource
        case missingSource
        case missingDestination
        case destinationIsMovingItem
        case invalidOrderKey
        case invalidResult
        case saveFailed(String)

        var code: String {
            switch self {
            case .duplicateSource: "ORDER-001"
            case .missingSource: "ORDER-002"
            case .missingDestination: "ORDER-003"
            case .destinationIsMovingItem: "ORDER-004"
            case .invalidOrderKey: "ORDER-005"
            case .invalidResult: "ORDER-006"
            case .saveFailed: "ORDER-007"
            }
        }

        var errorDescription: String? {
            switch self {
            case .duplicateSource:
                "Nagare couldn't save this order because the move contained the same item more than once. (\(code))"
            case .missingSource:
                "Nagare couldn't save this order because an item being moved could not be found. (\(code))"
            case .missingDestination:
                "Nagare couldn't save this order because the drop position could not be found. (\(code))"
            case .destinationIsMovingItem:
                "Nagare received an unexpected drop position and restored the previous order. (\(code))"
            case .invalidOrderKey:
                "Nagare found an invalid saved position and restored the previous order. (\(code))"
            case .invalidResult:
                "Nagare couldn't verify the new order and restored the previous order. (\(code))"
            case .saveFailed(let message):
                "Nagare couldn't write the new order. \(message) (\(code))"
            }
        }
    }

    enum MoveOutcome: Equatable {
        case noChange
        case saved
    }

    static func nextOrder(in context: ModelContext) throws -> String {
        try translateErrors {
            try ItemOrderingOrchestrator.prepareNextOrder(
                using: SwiftDataOrderingAdapter(context: context)
            )
        }
    }

    @discardableResult
    static func move(
        _ sourceIDs: [ItemID],
        to destinationDate: Date,
        before destinationID: ItemID?,
        in context: ModelContext,
        calendar: Calendar = .autoupdatingCurrent
    ) throws -> MoveOutcome {
        try translateErrors {
            switch try ItemOrderingOrchestrator.move(
                sourceIDs,
                to: destinationDate,
                before: destinationID,
                using: SwiftDataOrderingAdapter(context: context),
                calendar: calendar
            ) {
            case .noChange: .noChange
            case .saved: .saved
            }
        }
    }

    static func saveDisplayedOrder(
        _ itemIDs: [ItemID],
        on date: Date,
        in context: ModelContext,
        calendar: Calendar = .autoupdatingCurrent
    ) throws {
        try translateErrors {
            try ItemOrderingOrchestrator.saveDisplayedOrder(
                itemIDs,
                on: date,
                using: SwiftDataOrderingAdapter(context: context),
                calendar: calendar
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
                throw MoveError.duplicateSource
            case .missingSource:
                throw MoveError.missingSource
            case .missingDestination:
                throw MoveError.missingDestination
            case .destinationIsMovingValue:
                throw MoveError.destinationIsMovingItem
            case .invalidOrderKey:
                throw MoveError.invalidOrderKey
            case .invalidResult:
                throw MoveError.invalidResult
            }
        } catch let error as OrderingPersistenceError {
            throw MoveError.saveFailed(error.localizedDescription)
        } catch {
            throw MoveError.saveFailed(error.localizedDescription)
        }
    }
}
