import Foundation

struct PendingCalendarImport: Sendable {
    let fileURL: URL
    let draft: ICalendarEventDraft
}

enum PendingCalendarImportStore {
    private struct Envelope: Codable {
        let id: UUID
        let receivedAt: Date
        let draft: ICalendarEventDraft
    }

    enum StoreError: LocalizedError {
        case unavailableContainer
        case invalidQueueEntry(String)
        case invalidRemovalTarget

        var errorDescription: String? {
            switch self {
            case .unavailableContainer:
                "Nagare couldn't access its shared calendar inbox."
            case .invalidQueueEntry(let filename):
                "Nagare couldn't read the queued calendar invite \(filename)."
            case .invalidRemovalTarget:
                "Nagare refused to remove an unexpected calendar inbox file."
            }
        }
    }

    static func enqueue(
        _ draft: ICalendarEventDraft,
        id: UUID = UUID(),
        receivedAt: Date = .now
    ) throws {
        let directory = try queueDirectory()
        try FileManager.default.createDirectory(
            at: directory,
            withIntermediateDirectories: true
        )
        let envelope = Envelope(
            id: id,
            receivedAt: receivedAt,
            draft: draft
        )
        let data = try JSONEncoder().encode(envelope)
        try data.write(
            to: directory.appending(path: "\(id.uuidString).json"),
            options: .atomic
        )
    }

    static func pendingImports() throws -> [PendingCalendarImport] {
        let directory = try queueDirectory()
        guard FileManager.default.fileExists(atPath: directory.path) else {
            return []
        }
        let files = try FileManager.default.contentsOfDirectory(
            at: directory,
            includingPropertiesForKeys: nil
        )
        return try files
            .filter { $0.pathExtension.lowercased() == "json" }
            .sorted { $0.lastPathComponent < $1.lastPathComponent }
            .map { fileURL in
                do {
                    let data = try Data(contentsOf: fileURL)
                    let envelope = try JSONDecoder().decode(
                        Envelope.self,
                        from: data
                    )
                    return PendingCalendarImport(
                        fileURL: fileURL,
                        draft: envelope.draft
                    )
                } catch {
                    throw StoreError.invalidQueueEntry(
                        fileURL.lastPathComponent
                    )
                }
            }
    }

    static func remove(_ pendingImport: PendingCalendarImport) throws {
        let directory = try queueDirectory().standardizedFileURL
        let target = pendingImport.fileURL.standardizedFileURL
        guard target.deletingLastPathComponent() == directory,
              target.pathExtension.lowercased() == "json" else {
            throw StoreError.invalidRemovalTarget
        }
        try FileManager.default.removeItem(at: target)
    }

    private static func queueDirectory() throws -> URL {
        guard let container = FileManager.default.containerURL(
            forSecurityApplicationGroupIdentifier: NagareAppGroup.identifier
        ) else {
            throw StoreError.unavailableContainer
        }
        return container
            .appending(path: "Calendar Imports", directoryHint: .isDirectory)
            .appending(path: "Pending", directoryHint: .isDirectory)
    }
}
