import Foundation
import Testing
@testable import Nagare

struct ReorderProjectionTests {
    @Test func movesLastItemBeforeFirstItem() throws {
        let result = try ReorderProjection.applying(
            sources: ["third"],
            before: "first",
            to: ["first", "second", "third"]
        )

        #expect(result == ["third", "first", "second"])
    }

    @Test func movesFirstItemToEnd() throws {
        let result = try ReorderProjection.applying(
            sources: ["first"],
            before: nil,
            to: ["first", "second", "third"]
        )

        #expect(result == ["second", "third", "first"])
    }

    @Test func appliesListOffsetsWhenMovingSecondItemBeforeFirst() throws {
        let result = try ReorderProjection.applying(
            sourceOffsets: IndexSet(integer: 1),
            toOffset: 0,
            to: ["Hello", "Boot"]
        )

        #expect(result == ["Boot", "Hello"])
    }

    @Test func appliesListOffsetsWhenMovingFirstItemToEnd() throws {
        let result = try ReorderProjection.applying(
            sourceOffsets: IndexSet(integer: 0),
            toOffset: 2,
            to: ["Hello", "Boot"]
        )

        #expect(result == ["Boot", "Hello"])
    }

    @Test func preservesTheReportedOrderOfMultipleSources() throws {
        let result = try ReorderProjection.applying(
            sources: ["third", "first"],
            before: "second",
            to: ["first", "second", "third", "fourth"]
        )

        #expect(result == ["third", "first", "second", "fourth"])
    }

    @Test func rejectsUnexpectedInputInsteadOfFailingQuietly() {
        #expect(throws: ReorderProjection.ProjectionError.self) {
            try ReorderProjection.applying(
                sources: ["missing"],
                before: "first",
                to: ["first", "second"]
            )
        }
        #expect(throws: ReorderProjection.ProjectionError.self) {
            try ReorderProjection.applying(
                sources: ["first"],
                before: "first",
                to: ["first", "second"]
            )
        }
    }
}
