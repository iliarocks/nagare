import CoreTransferable
import Foundation
import UniformTypeIdentifiers

struct ICalendarExportFile {
    let data: Data
    let filename: String
    let subject: String

    init(event: EventRecordSnapshot, generatedAt: Date = .now) {
        let draft = ICalendarEventDraft(
            sourceIdentifier: event.calendarIdentifier
                ?? "\(event.id.uuidString)@nagare",
            title: event.title,
            notes: event.notes,
            scheduledDate: event.scheduledDate,
            endDate: event.endDate,
            isAllDay: false
        )
        data = ICalendarSerializer.serialize(draft, generatedAt: generatedAt)
        filename = Self.filename(for: event.title)
        subject = event.title.isEmpty ? "Event" : event.title
    }
}

/// A lazy, native share payload. The temporary file is created only after the
/// user invokes Share, so list rendering remains a pure projection of data.
struct ICalendarShareItem: Transferable {
    let event: EventRecordSnapshot

    static var transferRepresentation: some TransferRepresentation {
        FileRepresentation(exportedContentType: .calendarEvent) { item in
            let file = try ICalendarExportStore.write(
                ICalendarExportFile(event: item.event)
            )
            return SentTransferredFile(file.fileURL)
        }
    }
}

struct SharedCalendarFile: Identifiable {
    let id: UUID
    let fileURL: URL
    let subject: String
}

enum ICalendarExportStore {
    static func write(
        _ file: ICalendarExportFile,
        to baseDirectory: URL = FileManager.default.temporaryDirectory,
        id: UUID = UUID()
    ) throws -> SharedCalendarFile {
        let directory = baseDirectory.appending(
            path: id.uuidString,
            directoryHint: .isDirectory
        )
        try FileManager.default.createDirectory(
            at: directory,
            withIntermediateDirectories: true
        )
        let fileURL = directory.appending(path: file.filename)
        try file.data.write(to: fileURL, options: .atomic)
        return SharedCalendarFile(
            id: id,
            fileURL: fileURL,
            subject: file.subject
        )
    }
}

private extension ICalendarExportFile {
    private static func filename(for title: String) -> String {
        let forbidden = CharacterSet(
            charactersIn: "/\\?%*|\"<>:\n\r"
        )
        let cleaned = title
            .components(separatedBy: forbidden)
            .joined(separator: "-")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        let basename = cleaned.isEmpty ? "Event" : String(cleaned.prefix(80))
        return "\(basename).ics"
    }
}
