import Foundation

nonisolated enum NagareDataArchiveCodec {
    private struct Header: Decodable {
        let formatVersion: Int
    }

    static func encode(
        _ snapshot: NagareDataSnapshot,
        exportedAt: Date
    ) throws -> Data {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [
            .prettyPrinted,
            .sortedKeys,
            .withoutEscapingSlashes
        ]
        do {
            return try encoder.encode(
                NagareDataArchive(snapshot: snapshot, exportedAt: exportedAt)
            )
        } catch {
            throw NagareDataArchiveError.couldNotEncode
        }
    }

    static func decode(_ data: Data) throws -> NagareDataArchive {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        do {
            let header = try decoder.decode(Header.self, from: data)
            switch header.formatVersion {
            case NagareDataArchive.currentFormatVersion:
                return try decoder.decode(NagareDataArchive.self, from: data)
            case 1:
                return try decoder.decode(
                    LegacyNagareDataArchiveV1.self,
                    from: data
                ).unified()
            default:
                throw NagareDataArchiveError.unsupportedVersion(
                    header.formatVersion
                )
            }
        } catch let error as NagareDataArchiveError {
            throw error
        } catch {
            throw NagareDataArchiveError.invalidFile
        }
    }
}

nonisolated enum NagareDataArchivePlanner {
    static func planImport(
        _ archive: NagareDataArchive,
        into current: NagareDataSnapshot,
        calendar: Calendar
    ) throws -> NagareDataImportPlan {
        guard archive.formatVersion == NagareDataArchive.currentFormatVersion
        else {
            throw NagareDataArchiveError.unsupportedVersion(
                archive.formatVersion
            )
        }

        let projectIDs = try uniqueIDs(
            archive.projects.map(\.id),
            kind: "project"
        )
        _ = try uniqueIDs(archive.todos.map(\.id), kind: "todo")
        let templateIDs = try uniqueIDs(
            archive.recurrenceTemplates.map(\.id),
            kind: "recurrence"
        )
        let todosByID = Dictionary(
            uniqueKeysWithValues: archive.todos.map { ($0.id, $0) }
        )

        try validateProjectReferences(
            projects: projectIDs,
            todos: archive.todos,
            templates: archive.recurrenceTemplates
        )

        var validatedTemplates: [NagareDataImportTemplate] = []
        for template in archive.recurrenceTemplates {
            let rule = try rule(for: template, calendar: calendar)
            guard let currentItem = todosByID[template.currentItemID],
                  currentItem.completedAt == nil,
                  currentItem.recurrenceTemplateID == template.id,
                  currentItem.recurrenceSequence
                    == template.currentSequence else {
                throw NagareDataArchiveError.missingCurrentItem(template.id)
            }
            try validateTimes(template)
            validatedTemplates.append(
                NagareDataImportTemplate(record: template, rule: rule)
            )
        }

        for todo in archive.todos {
            guard let templateID = todo.recurrenceTemplateID else { continue }
            guard templateIDs.contains(templateID) else {
                throw NagareDataArchiveError.missingRecurrence(
                    templateID,
                    recordID: todo.id
                )
            }
            guard todo.recurrenceSequence != nil else {
                throw NagareDataArchiveError.invalidRecurrence(
                    templateID,
                    detail: "todo occurrence is missing its sequence"
                )
            }
        }

        let createdCount = archive.projects.count(where: {
            current.projectsByID[$0.id] == nil
        }) + archive.todos.count(where: {
            current.todosByID[$0.id] == nil
        }) + archive.recurrenceTemplates.count(where: {
            current.templatesByID[$0.id] == nil
        })
        let totalCount = archive.projects.count
            + archive.todos.count
            + archive.recurrenceTemplates.count
        let summary = NagareDataImportSummary(
            projectCount: archive.projects.count,
            todoCount: archive.todos.count,
            recurrenceCount: archive.recurrenceTemplates.count,
            createdCount: createdCount,
            updatedCount: totalCount - createdCount
        )

        return NagareDataImportPlan(
            projects: archive.projects.sorted(by: idOrder),
            todos: archive.todos.sorted(by: idOrder),
            recurrenceTemplates: validatedTemplates.sorted {
                $0.record.id.uuidString < $1.record.id.uuidString
            },
            summary: summary
        )
    }

    private static func uniqueIDs(
        _ ids: [UUID],
        kind: String
    ) throws -> Set<UUID> {
        var result: Set<UUID> = []
        for id in ids where !result.insert(id).inserted {
            throw NagareDataArchiveError.duplicateID(kind: kind, id: id)
        }
        return result
    }

    private static func validateProjectReferences(
        projects: Set<UUID>,
        todos: [NagareArchiveTodo],
        templates: [NagareArchiveRecurrenceTemplate]
    ) throws {
        for (recordID, projectID) in todos.compactMap({ record in
            record.projectID.map { (record.id, $0) }
        }) + templates.compactMap({ record in
            record.projectID.map { (record.id, $0) }
        }) where !projects.contains(projectID) {
            throw NagareDataArchiveError.missingProject(
                projectID,
                recordID: recordID
            )
        }
    }

    private static func validateTimes(
        _ template: NagareArchiveRecurrenceTemplate
    ) throws {
        guard let start = template.startTimeSeconds else {
            guard template.endTimeSeconds == nil else {
                throw NagareDataArchiveError.invalidRecurrence(
                    template.id,
                    detail: "end time has no start time"
                )
            }
            return
        }
        guard (0..<86_400).contains(start) else {
            throw NagareDataArchiveError.invalidRecurrence(
                template.id,
                detail: "invalid start time"
            )
        }
        if let end = template.endTimeSeconds,
           (!(0..<86_400).contains(end) || end < start) {
            throw NagareDataArchiveError.invalidRecurrence(
                template.id,
                detail: "invalid end time"
            )
        }
    }

    private static func rule(
        for template: NagareArchiveRecurrenceTemplate,
        calendar: Calendar
    ) throws -> RecurrenceRule {
        guard let mode = RecurrenceMode(rawValue: template.modeRawValue),
              let unit = RecurrenceUnit(rawValue: template.unitRawValue) else {
            throw NagareDataArchiveError.invalidRecurrence(
                template.id,
                detail: "unknown mode or unit"
            )
        }
        do {
            switch mode {
            case .relative:
                return try .relative(every: template.interval, unit: unit)
            case .absolute:
                guard let reference = template.reference else {
                    throw NagareDataArchiveError.invalidRecurrence(
                        template.id,
                        detail: "missing reference date"
                    )
                }
                return try .absolute(
                    every: template.interval,
                    unit: unit,
                    anchors: template.anchors,
                    reference: reference,
                    calendar: calendar
                )
            }
        } catch let error as NagareDataArchiveError {
            throw error
        } catch {
            throw NagareDataArchiveError.invalidRecurrence(
                template.id,
                detail: error.localizedDescription
            )
        }
    }

    private static func idOrder<Record>(
        _ lhs: Record,
        _ rhs: Record
    ) -> Bool where Record: NagareArchiveIdentifiable {
        lhs.id.uuidString < rhs.id.uuidString
    }
}

private nonisolated protocol NagareArchiveIdentifiable {
    var id: UUID { get }
}

extension NagareArchiveProject: NagareArchiveIdentifiable {}
extension NagareArchiveTodo: NagareArchiveIdentifiable {}

/// Exact decoder for the pre-unification export shape. It is intentionally
/// private so Event cannot leak back into current application code.
private nonisolated struct LegacyNagareDataArchiveV1: Decodable {
    let exportedAt: Date
    let projects: [NagareArchiveProject]
    let todos: [LegacyTodo]
    let events: [LegacyEvent]
    let recurrenceTemplates: [LegacyTemplate]

    func unified() -> NagareDataArchive {
        NagareDataArchive(
            exportedAt: exportedAt,
            projects: projects,
            todos: todos.map(\.unified) + events.map(\.unified),
            recurrenceTemplates: recurrenceTemplates.map(\.unified)
        )
    }

    struct LegacyTodo: Decodable {
        let id: UUID
        let createdAt: Date
        let title: String
        let notes: String?
        let scheduledDate: Date
        let completedAt: Date?
        let order: String
        let projectOrder: String?
        let recurrenceSequence: Int?
        let recurrenceTemplateID: UUID?
        let projectID: UUID?

        var unified: NagareArchiveTodo {
            NagareArchiveTodo(
                id: id,
                createdAt: createdAt,
                title: title,
                notes: notes,
                scheduledDate: scheduledDate,
                completedAt: completedAt,
                order: order,
                projectOrder: projectOrder,
                recurrenceSequence: recurrenceSequence,
                recurrenceTemplateID: recurrenceTemplateID,
                projectID: projectID
            )
        }
    }

    struct LegacyEvent: Decodable {
        let id: UUID
        let createdAt: Date
        let title: String
        let notes: String?
        let scheduledDate: Date
        let endDate: Date?
        let calendarIdentifier: String?
        let order: String
        let projectOrder: String?
        let recurrenceSequence: Int?
        let recurrenceTemplateID: UUID?
        let projectID: UUID?

        var unified: NagareArchiveTodo {
            NagareArchiveTodo(
                id: id,
                createdAt: createdAt,
                title: title,
                notes: notes,
                scheduledDate: scheduledDate,
                includesTime: true,
                endDate: endDate,
                calendarIdentifier: calendarIdentifier,
                completedAt: nil,
                order: order,
                projectOrder: projectOrder,
                recurrenceSequence: recurrenceSequence,
                recurrenceTemplateID: recurrenceTemplateID,
                projectID: projectID
            )
        }
    }

    struct LegacyTemplate: Decodable {
        let id: UUID
        let createdAt: Date
        let title: String
        let notes: String?
        let modeRawValue: String
        let unitRawValue: String
        let interval: Int
        let anchors: [Int]
        let reference: Date?
        let startTimeSeconds: Int?
        let endTimeSeconds: Int?
        let currentItemID: UUID
        let currentSequence: Int
        let projectID: UUID?

        var unified: NagareArchiveRecurrenceTemplate {
            NagareArchiveRecurrenceTemplate(
                id: id,
                createdAt: createdAt,
                title: title,
                notes: notes,
                modeRawValue: modeRawValue,
                unitRawValue: unitRawValue,
                interval: interval,
                anchors: anchors,
                reference: reference,
                startTimeSeconds: startTimeSeconds,
                endTimeSeconds: endTimeSeconds,
                currentItemID: currentItemID,
                currentSequence: currentSequence,
                projectID: projectID
            )
        }
    }
}

nonisolated enum NagareDataArchiveError: Error, LocalizedError, Equatable {
    case couldNotEncode
    case invalidFile
    case unsupportedVersion(Int)
    case duplicateID(kind: String, id: UUID)
    case missingProject(UUID, recordID: UUID)
    case missingRecurrence(UUID, recordID: UUID)
    case missingCurrentItem(UUID)
    case invalidRecurrence(UUID, detail: String)

    var errorDescription: String? {
        switch self {
        case .couldNotEncode:
            "Nagare couldn't create the export file."
        case .invalidFile:
            "This isn't a valid Nagare data file."
        case .unsupportedVersion(let version):
            "This file uses unsupported Nagare data format version \(version)."
        case .duplicateID(let kind, let id):
            "The file contains duplicate \(kind) ID \(id.uuidString)."
        case .missingProject(let projectID, let recordID):
            "Record \(recordID.uuidString) refers to missing project \(projectID.uuidString)."
        case .missingRecurrence(let templateID, let recordID):
            "Record \(recordID.uuidString) refers to missing recurrence \(templateID.uuidString)."
        case .missingCurrentItem(let templateID):
            "Recurrence \(templateID.uuidString) is missing its current Todo."
        case .invalidRecurrence(let id, let detail):
            "Recurrence \(id.uuidString) is invalid: \(detail)."
        }
    }
}
