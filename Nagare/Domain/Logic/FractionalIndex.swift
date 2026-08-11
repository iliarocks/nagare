import Foundation

nonisolated enum FractionalIndex {
    private static let characters = Array("0123456789abcdefghijklmnopqrstuvwxyz")
    private static let characterIndexes = Dictionary(
        uniqueKeysWithValues: characters.enumerated().map { ($1, $0) }
    )
    private static let rebalanceWidth = 12

    static func between(_ before: String?, _ after: String?) -> String? {
        guard before.map(isValid) ?? true,
              after.map(isValid) ?? true else {
            return nil
        }

        if let before, let after, before >= after {
            return nil
        }

        let candidate = midpoint(before ?? "", after ?? "")
        guard !candidate.isEmpty,
              before.map({ $0 < candidate }) ?? true,
              after.map({ candidate < $0 }) ?? true else {
            return nil
        }
        return candidate
    }

    static func between(
        count: Int,
        _ before: String?,
        _ after: String?
    ) -> [String]? {
        guard count >= 0 else {
            return nil
        }

        var keys: [String] = []
        var lowerBound = before

        for _ in 0..<count {
            guard let key = between(lowerBound, after) else {
                return nil
            }
            keys.append(key)
            lowerBound = key
        }

        return keys
    }

    static func isValid(_ key: String) -> Bool {
        !key.isEmpty && key.allSatisfy { characterIndexes[$0] != nil }
    }

    static func rebalancedKeys(count: Int) -> [String] {
        guard count > 0 else {
            return []
        }

        let maximum = power(UInt64(characters.count), rebalanceWidth) - 1
        guard UInt64(count) < maximum else {
            return []
        }
        let step = maximum / (UInt64(count) + 1)

        return (1...count).map { index in
            encode(UInt64(index) * step, width: rebalanceWidth)
        }
    }

    private static func midpoint(_ lower: String, _ upper: String) -> String {
        let lowerCharacters = Array(lower)
        var upperCharacters = Array(upper)
        var result = ""
        var index = 0

        while true {
            let lowerIndex: Int
            if index < lowerCharacters.count {
                lowerIndex = characterIndexes[lowerCharacters[index]] ?? 0
            } else {
                lowerIndex = 0
            }

            let upperIndex: Int
            if index < upperCharacters.count {
                upperIndex = characterIndexes[upperCharacters[index]] ?? characters.count
            } else {
                upperIndex = characters.count
            }

            if lowerIndex + 1 < upperIndex {
                return result + String(characters[(lowerIndex + upperIndex) / 2])
            }

            result.append(characters[lowerIndex])
            if lowerIndex < upperIndex {
                upperCharacters = []
            }
            index += 1
        }
    }

    private static func encode(_ value: UInt64, width: Int) -> String {
        var value = value
        var output = Array(repeating: characters[0], count: width)

        for index in output.indices.reversed() {
            output[index] = characters[Int(value % UInt64(characters.count))]
            value /= UInt64(characters.count)
        }

        return String(output)
    }

    private static func power(_ base: UInt64, _ exponent: Int) -> UInt64 {
        (0..<exponent).reduce(1) { result, _ in result * base }
    }
}
