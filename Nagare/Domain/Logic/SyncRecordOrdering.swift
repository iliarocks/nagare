import Foundation

/// One canonical ordering for every replicated-record conflict. Store-local
/// identity is consulted only after every replicated value compares equal.
nonisolated enum SyncRecordOrdering {
    static func canonical<Record>(
        _ records: [Record],
        metadata: KeyPath<Record, SyncRecordMetadata>
    ) -> Record {
        precondition(!records.isEmpty)
        return records.max {
            isLowerPriority(
                $0[keyPath: metadata],
                than: $1[keyPath: metadata]
            )
        }!
    }

    static func isLowerPriority(
        _ first: SyncRecordMetadata,
        than second: SyncRecordMetadata
    ) -> Bool {
        if first.revisionDate != second.revisionDate {
            return first.revisionDate < second.revisionDate
        }
        if first.createdAt != second.createdAt {
            return first.createdAt < second.createdAt
        }
        if first.resolvedPhysicalID != second.resolvedPhysicalID {
            return first.resolvedPhysicalID.uuidString
                < second.resolvedPhysicalID.uuidString
        }
        if first.stableTieBreaker != second.stableTieBreaker {
            return lexicographicallyPrecedes(
                first.stableTieBreaker,
                second.stableTieBreaker
            )
        }

        // The records are replicated-value-equivalent. This last comparison
        // merely gives a local adapter one concrete object to retain.
        return first.reference.localID < second.reference.localID
    }

    private static func lexicographicallyPrecedes(
        _ first: [String],
        _ second: [String]
    ) -> Bool {
        for (left, right) in zip(first, second) where left != right {
            return left < right
        }
        return first.count < second.count
    }
}
