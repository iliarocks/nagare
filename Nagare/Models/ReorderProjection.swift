import Foundation

nonisolated enum ReorderProjection {
    enum ProjectionError: LocalizedError {
        case duplicateSource
        case missingSource
        case missingDestination
        case destinationIsMovingItem
        case invalidSourceOffset
        case invalidDestinationOffset

        var errorDescription: String? {
            switch self {
            case .duplicateSource:
                "Nagare received the same dragged item more than once. (ORDER-UI-001)"
            case .missingSource:
                "Nagare couldn't find an item being dragged. (ORDER-UI-002)"
            case .missingDestination:
                "Nagare couldn't find the drop position. (ORDER-UI-003)"
            case .destinationIsMovingItem:
                "Nagare received an invalid drop position. (ORDER-UI-004)"
            case .invalidSourceOffset:
                "Nagare received an invalid item position from the list. (ORDER-UI-007)"
            case .invalidDestinationOffset:
                "Nagare received an invalid destination position from the list. (ORDER-UI-008)"
            }
        }
    }

    static func applying<Value>(
        sourceOffsets: IndexSet,
        toOffset destinationOffset: Int,
        to values: [Value]
    ) throws -> [Value] {
        guard sourceOffsets.allSatisfy({ values.indices.contains($0) }) else {
            throw ProjectionError.invalidSourceOffset
        }
        guard (0...values.count).contains(destinationOffset) else {
            throw ProjectionError.invalidDestinationOffset
        }

        let movingValues = sourceOffsets.map { values[$0] }
        let remainingValues = values.enumerated().compactMap { index, value in
            sourceOffsets.contains(index) ? nil : value
        }
        let removedBeforeDestination = sourceOffsets.count(in: 0..<destinationOffset)
        let insertionIndex = destinationOffset - removedBeforeDestination
        guard (0...remainingValues.count).contains(insertionIndex) else {
            throw ProjectionError.invalidDestinationOffset
        }

        var result = remainingValues
        result.insert(contentsOf: movingValues, at: insertionIndex)
        return result
    }

    static func applying<ID: Hashable>(
        sources: [ID],
        before destination: ID?,
        to values: [ID]
    ) throws -> [ID] {
        let sourceSet = Set(sources)
        guard sourceSet.count == sources.count else {
            throw ProjectionError.duplicateSource
        }
        guard sources.allSatisfy(values.contains) else {
            throw ProjectionError.missingSource
        }
        if let destination, sourceSet.contains(destination) {
            throw ProjectionError.destinationIsMovingItem
        }

        var result = values.filter { !sourceSet.contains($0) }
        let insertionIndex: Int
        if let destination {
            guard let index = result.firstIndex(of: destination) else {
                throw ProjectionError.missingDestination
            }
            insertionIndex = index
        } else {
            insertionIndex = result.endIndex
        }
        result.insert(contentsOf: sources, at: insertionIndex)
        return result
    }
}
