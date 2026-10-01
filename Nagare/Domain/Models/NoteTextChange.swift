import Foundation

/// Only fields the user edited cross the write boundary. The repository applies
/// them to its fresh record, preserving unrelated edits received through sync.
nonisolated enum NoteTextChange: Equatable, Sendable {
    case title(String)
    case notes(String?)
}
