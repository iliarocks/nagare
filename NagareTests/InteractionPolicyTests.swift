import Testing
@testable import Nagare

@MainActor
struct InteractionPolicyTests {
    @Test func adjacentSelectionsFormOneVisualGroup() {
        let orderedIDs = [1, 2, 3, 4, 5]
        let selectedIDs: Set = [2, 3, 4]

        #expect(
            NagareSelectionPosition.resolve(
                id: 1,
                orderedIDs: orderedIDs,
                selectedIDs: selectedIDs
            ) == .none
        )
        #expect(
            NagareSelectionPosition.resolve(
                id: 2,
                orderedIDs: orderedIDs,
                selectedIDs: selectedIDs
            ) == .first
        )
        #expect(
            NagareSelectionPosition.resolve(
                id: 3,
                orderedIDs: orderedIDs,
                selectedIDs: selectedIDs
            ) == .middle
        )
        #expect(
            NagareSelectionPosition.resolve(
                id: 4,
                orderedIDs: orderedIDs,
                selectedIDs: selectedIDs
            ) == .last
        )
    }

    @Test func isolatedSelectionUsesAllRoundedCorners() {
        #expect(
            NagareSelectionPosition.resolve(
                id: "selected",
                orderedIDs: ["before", "selected", "after"],
                selectedIDs: ["selected"]
            ) == .single
        )
    }
}
