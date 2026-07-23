import Testing
@testable import Nagare

struct FractionalIndexTests {
    @Test func createsInitialKeyWithoutBounds() {
        let key = FractionalIndex.between(nil, nil)

        #expect(key != nil)
        #expect(key.map(FractionalIndex.isValid) == true)
    }

    @Test func createsKeyAfterLowerBound() {
        let key = FractionalIndex.between("i", nil)

        #expect(key != nil)
        #expect(key.map { "i" < $0 } == true)
    }

    @Test func createsKeyBeforeUpperBound() {
        let key = FractionalIndex.between(nil, "i")

        #expect(key != nil)
        #expect(key.map { $0 < "i" } == true)
    }

    @Test func createsKeyBetweenBounds() {
        let key = FractionalIndex.between("9", "i")

        #expect(key != nil)
        #expect(key.map { "9" < $0 && $0 < "i" } == true)
    }

    @Test func createsLongerKeyBetweenAdjacentCharacters() {
        let key = FractionalIndex.between("a", "b")

        #expect(key != nil)
        #expect(key.map { "a" < $0 && $0 < "b" } == true)
    }

    @Test func returnsNilWhenNoRepresentableKeyExists() {
        #expect(FractionalIndex.between(nil, "0") == nil)
        #expect(FractionalIndex.between("a", "a0") == nil)
    }

    @Test func rejectsEqualOrReversedBounds() {
        #expect(FractionalIndex.between("i", "i") == nil)
        #expect(FractionalIndex.between("r", "i") == nil)
    }

    @Test func rejectsEmptyAndUnsupportedKeys() {
        #expect(!FractionalIndex.isValid(""))
        #expect(!FractionalIndex.isValid("A"))
        #expect(!FractionalIndex.isValid("a-1"))
        #expect(FractionalIndex.between("A", nil) == nil)
        #expect(FractionalIndex.between(nil, "a-") == nil)
    }

    @Test func createsSeveralOrderedKeysBetweenBounds() throws {
        let keys = try #require(FractionalIndex.between(count: 25, "a", "b"))

        #expect(keys.count == 25)
        #expect(Set(keys).count == keys.count)
        #expect(keys == keys.sorted())
        #expect(keys.allSatisfy { "a" < $0 && $0 < "b" })
    }

    @Test func handlesZeroAndNegativeKeyCounts() {
        #expect(FractionalIndex.between(count: 0, "a", "b") == [])
        #expect(FractionalIndex.between(count: -1, "a", "b") == nil)
    }

    @Test func rebalancedKeysAreOrderedUniqueAndFixedWidth() {
        for count in [1, 2, 3, 10, 100, 1_000] {
            let keys = FractionalIndex.rebalancedKeys(count: count)

            #expect(keys.count == count)
            #expect(Set(keys).count == count)
            #expect(keys == keys.sorted())
            #expect(keys.allSatisfy(FractionalIndex.isValid))
            #expect(keys.allSatisfy { $0.count == 12 })
        }
    }

    @Test func rebalancedKeysHandleEmptyCounts() {
        #expect(FractionalIndex.rebalancedKeys(count: 0) == [])
        #expect(FractionalIndex.rebalancedKeys(count: -1) == [])
    }

    @Test func repeatedlyAppendsWithoutBreakingOrdering() throws {
        var keys: [String] = []

        for _ in 0..<1_000 {
            let key = try #require(FractionalIndex.between(keys.last, nil))
            keys.append(key)
        }

        #expect(keys == keys.sorted())
        #expect(Set(keys).count == keys.count)
        #expect(keys.allSatisfy(FractionalIndex.isValid))
    }

    @Test func repeatedRandomInsertionsPreserveOrdering() throws {
        var generator = SeededGenerator(seed: 0x4e_61_67_61_72_65)
        var keys: [String] = []

        for _ in 0..<750 {
            let insertionIndex = Int.random(
                in: 0...keys.count,
                using: &generator
            )
            var before = insertionIndex > 0 ? keys[insertionIndex - 1] : nil
            var after = insertionIndex < keys.count ? keys[insertionIndex] : nil
            var candidate = FractionalIndex.between(before, after)

            if candidate == nil {
                keys = FractionalIndex.rebalancedKeys(count: keys.count)
                before = insertionIndex > 0 ? keys[insertionIndex - 1] : nil
                after = insertionIndex < keys.count ? keys[insertionIndex] : nil
                candidate = FractionalIndex.between(before, after)
            }

            keys.insert(try #require(candidate), at: insertionIndex)
            #expect(keys == keys.sorted())
            #expect(Set(keys).count == keys.count)
        }
    }

    @Test func everyGeneratedKeySatisfiesItsBounds() {
        let keys = FractionalIndex.rebalancedKeys(count: 200)

        for index in 0...keys.count {
            let before = index > 0 ? keys[index - 1] : nil
            let after = index < keys.count ? keys[index] : nil

            if let key = FractionalIndex.between(before, after) {
                #expect(before.map { $0 < key } ?? true)
                #expect(after.map { key < $0 } ?? true)
                #expect(FractionalIndex.isValid(key))
            }
        }
    }
}

private struct SeededGenerator: RandomNumberGenerator {
    private var state: UInt64

    init(seed: UInt64) {
        state = seed
    }

    mutating func next() -> UInt64 {
        state = state &* 6_364_136_223_846_793_005 &+ 1
        return state
    }
}
