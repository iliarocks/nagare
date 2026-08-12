import Foundation

/// Metadata shared by every independently synchronized record. The semantic
/// `id` can intentionally collide after concurrent creation, while the
/// physical `syncRecordID` gives that record a replicated tie-breaker.
/// Optional sync metadata keeps the V1-to-V2 migration additive and lossless;
/// repair assigns missing physical IDs and the transaction boundary stamps
/// `modifiedAt` before every subsequent local commit.
protocol SyncRecord: AnyObject {
    var id: UUID { get }
    var createdAt: Date { get }
    var modifiedAt: Date? { get set }
    var syncRecordID: UUID? { get set }
}

extension SyncRecord {
    var syncModificationDate: Date {
        modifiedAt ?? createdAt
    }
}
