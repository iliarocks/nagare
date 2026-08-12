import Foundation

/// Canonical text encoding for replicated-value tie breakers. Every conflict
/// policy uses this one implementation so exact timestamp ties cannot diverge
/// because two layers serialize an optional or date differently.
nonisolated enum SyncStableValue {
    static func encode(_ value: String) -> String {
        "s:\(Data(value.utf8).base64EncodedString())"
    }

    static func encode(_ value: String?) -> String {
        value.map(encode) ?? "nil"
    }

    static func encode(_ value: Bool) -> String {
        value ? "b:1" : "b:0"
    }

    static func encode(_ value: Int) -> String {
        "i:\(value)"
    }

    static func encode(_ value: Int?) -> String {
        value.map(encode) ?? "nil"
    }

    static func encode(_ value: [Int]) -> String {
        "a:" + value.map(String.init).joined(separator: ",")
    }

    static func encode(_ value: Date) -> String {
        "d:\(value.timeIntervalSinceReferenceDate.bitPattern)"
    }

    static func encode(_ value: Date?) -> String {
        value.map(encode) ?? "nil"
    }

    static func encode(_ value: UUID) -> String {
        "u:\(value.uuidString)"
    }

    static func encode(_ value: UUID?) -> String {
        value.map(encode) ?? "nil"
    }
}
