import Foundation

struct ICalendarEventDraft: Codable, Equatable, Sendable {
    let sourceIdentifier: String
    let title: String
    let notes: String?
    let scheduledDate: Date
    let endDate: Date?
    let isAllDay: Bool
}

enum ICalendarError: LocalizedError, Equatable {
    case unreadableData
    case missingEvent
    case missingStartDate
    case invalidDate(String)
    case invalidEndDate
    case unsupportedTimeZone(String)
    case cancelledEvent

    var errorDescription: String? {
        switch self {
        case .unreadableData:
            "Nagare couldn't read this calendar file."
        case .missingEvent:
            "This calendar file doesn't contain an event."
        case .missingStartDate:
            "This calendar event doesn't have a start date."
        case .invalidDate(let value):
            "Nagare couldn't understand the calendar date \(value)."
        case .invalidEndDate:
            "The calendar event ends before it starts."
        case .unsupportedTimeZone(let identifier):
            "Nagare doesn't recognize the calendar time zone \(identifier)."
        case .cancelledEvent:
            "This calendar invite has been cancelled."
        }
    }
}

enum ICalendarParser {
    private struct ContentLine {
        let name: String
        let parameters: [String: String]
        let value: String
        let rawValue: String
    }

    static func parse(
        _ data: Data,
        defaultTimeZone: TimeZone
    ) throws -> ICalendarEventDraft {
        guard let text = String(data: data, encoding: .utf8)
            ?? String(data: data, encoding: .isoLatin1) else {
            throw ICalendarError.unreadableData
        }
        return try parse(text, defaultTimeZone: defaultTimeZone)
    }

    static func parse(
        _ text: String,
        defaultTimeZone: TimeZone
    ) throws -> ICalendarEventDraft {
        let events = eventContentLines(in: unfoldedLines(in: text))
        guard let lines = events.first else {
            throw ICalendarError.missingEvent
        }

        if value(named: "STATUS", in: lines)?.uppercased() == "CANCELLED" {
            throw ICalendarError.cancelledEvent
        }

        guard let startLine = first(named: "DTSTART", in: lines) else {
            throw ICalendarError.missingStartDate
        }
        let start = try date(
            from: startLine,
            defaultTimeZone: defaultTimeZone
        )
        let isAllDay = startLine.parameters["VALUE"]?.uppercased() == "DATE"
            || isDateOnly(startLine.value)

        var endDate: Date?
        if !isAllDay, let endLine = first(named: "DTEND", in: lines) {
            endDate = try date(
                from: endLine,
                defaultTimeZone: defaultTimeZone
            )
            if let endDate, endDate <= start {
                throw ICalendarError.invalidEndDate
            }
        }

        let summary = unescape(value(named: "SUMMARY", in: lines) ?? "")
        let description = normalizedText(
            unescape(value(named: "DESCRIPTION", in: lines) ?? "")
        )
        let location = normalizedText(
            unescape(value(named: "LOCATION", in: lines) ?? "")
        )
        let notes = combinedNotes(description: description, location: location)
        let identifier = normalizedText(value(named: "UID", in: lines))
            ?? generatedIdentifier(for: lines)

        return ICalendarEventDraft(
            sourceIdentifier: identifier,
            title: summary,
            notes: notes,
            scheduledDate: start,
            endDate: endDate,
            isAllDay: isAllDay
        )
    }

    private static func unfoldedLines(in text: String) -> [String] {
        let physicalLines = text
            .replacingOccurrences(of: "\r\n", with: "\n")
            .replacingOccurrences(of: "\r", with: "\n")
            .split(separator: "\n", omittingEmptySubsequences: false)
            .map(String.init)

        return physicalLines.reduce(into: [String]()) { lines, line in
            if (line.first == " " || line.first == "\t"), !lines.isEmpty {
                lines[lines.count - 1] += line.dropFirst()
            } else {
                lines.append(line)
            }
        }
    }

    private static func eventContentLines(
        in lines: [String]
    ) -> [[ContentLine]] {
        var events: [[ContentLine]] = []
        var current: [ContentLine]?
        var nestedComponentDepth = 0

        for rawLine in lines {
            guard let line = contentLine(from: rawLine) else { continue }
            let component = line.value.uppercased()

            if line.name == "BEGIN" {
                if component == "VEVENT", current == nil {
                    current = []
                    nestedComponentDepth = 0
                } else if current != nil {
                    nestedComponentDepth += 1
                }
                continue
            }

            if line.name == "END", current != nil {
                if component == "VEVENT", nestedComponentDepth == 0 {
                    events.append(current ?? [])
                    current = nil
                } else if nestedComponentDepth > 0 {
                    nestedComponentDepth -= 1
                }
                continue
            }

            if current != nil, nestedComponentDepth == 0 {
                current?.append(line)
            }
        }

        return events
    }

    private static func contentLine(from rawLine: String) -> ContentLine? {
        guard let separator = rawLine.firstIndex(of: ":") else {
            return nil
        }
        let header = rawLine[..<separator].split(separator: ";")
        guard let rawName = header.first else { return nil }

        var parameters: [String: String] = [:]
        for parameter in header.dropFirst() {
            let pair = parameter.split(separator: "=", maxSplits: 1)
            guard pair.count == 2 else { continue }
            parameters[pair[0].uppercased()] = pair[1]
                .trimmingCharacters(in: CharacterSet(charactersIn: "\""))
        }

        let value = String(rawLine[rawLine.index(after: separator)...])
        return ContentLine(
            name: rawName.uppercased(),
            parameters: parameters,
            value: value,
            rawValue: rawLine
        )
    }

    private static func first(
        named name: String,
        in lines: [ContentLine]
    ) -> ContentLine? {
        lines.first { $0.name == name }
    }

    private static func value(
        named name: String,
        in lines: [ContentLine]
    ) -> String? {
        first(named: name, in: lines)?.value
    }

    private static func date(
        from line: ContentLine,
        defaultTimeZone: TimeZone
    ) throws -> Date {
        if line.parameters["VALUE"]?.uppercased() == "DATE"
            || isDateOnly(line.value) {
            return try dateOnly(line.value, timeZone: defaultTimeZone)
        }

        let timeZone: TimeZone
        let value: String
        if line.value.uppercased().hasSuffix("Z") {
            timeZone = TimeZone(secondsFromGMT: 0)!
            value = String(line.value.dropLast())
        } else if let identifier = line.parameters["TZID"] {
            guard let parsedTimeZone = resolvedTimeZone(
                identifier: identifier
            ) else {
                throw ICalendarError.unsupportedTimeZone(identifier)
            }
            timeZone = parsedTimeZone
            value = line.value
        } else {
            timeZone = defaultTimeZone
            value = line.value
        }

        for format in ["yyyyMMdd'T'HHmmss", "yyyyMMdd'T'HHmm"] {
            let formatter = DateFormatter()
            formatter.calendar = Calendar(identifier: .gregorian)
            formatter.locale = Locale(identifier: "en_US_POSIX")
            formatter.timeZone = timeZone
            formatter.dateFormat = format
            formatter.isLenient = false
            if let date = formatter.date(from: value) {
                return date
            }
        }

        throw ICalendarError.invalidDate(line.value)
    }

    private static func dateOnly(
        _ value: String,
        timeZone: TimeZone
    ) throws -> Date {
        guard value.count == 8,
              let year = Int(value.prefix(4)),
              let month = Int(value.dropFirst(4).prefix(2)),
              let day = Int(value.suffix(2)) else {
            throw ICalendarError.invalidDate(value)
        }
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = timeZone
        guard let result = calendar.date(
            from: DateComponents(year: year, month: month, day: day)
        ) else {
            throw ICalendarError.invalidDate(value)
        }
        return result
    }

    private static func resolvedTimeZone(identifier: String) -> TimeZone? {
        if let exact = TimeZone(identifier: identifier) {
            return exact
        }
        let components = identifier.split(separator: "/")
        guard components.count > 2 else { return nil }
        return TimeZone(
            identifier: components.suffix(2).joined(separator: "/")
        )
    }

    private static func isDateOnly(_ value: String) -> Bool {
        value.count == 8 && value.allSatisfy(\.isNumber)
    }

    private static func unescape(_ value: String) -> String {
        var result = ""
        var isEscaped = false
        for character in value {
            if isEscaped {
                switch character {
                case "n", "N": result.append("\n")
                default: result.append(character)
                }
                isEscaped = false
            } else if character == "\\" {
                isEscaped = true
            } else {
                result.append(character)
            }
        }
        if isEscaped { result.append("\\") }
        return result
    }

    private static func normalizedText(_ value: String?) -> String? {
        guard let trimmed = value?.trimmingCharacters(
            in: .whitespacesAndNewlines
        ), !trimmed.isEmpty else {
            return nil
        }
        return trimmed
    }

    private static func combinedNotes(
        description: String?,
        location: String?
    ) -> String? {
        switch (description, location) {
        case let (.some(description), .some(location)):
            "\(description)\n\nLocation: \(location)"
        case let (.some(description), .none):
            description
        case let (.none, .some(location)):
            "Location: \(location)"
        case (.none, .none):
            nil
        }
    }

    private static func generatedIdentifier(
        for lines: [ContentLine]
    ) -> String {
        var hash: UInt64 = 14_695_981_039_346_656_037
        for byte in lines.map(\.rawValue).joined(separator: "\n").utf8 {
            hash ^= UInt64(byte)
            hash &*= 1_099_511_628_211
        }
        return "import-\(String(hash, radix: 16))@nagare"
    }
}

enum ICalendarSerializer {
    static func serialize(
        _ event: ICalendarEventDraft,
        generatedAt: Date
    ) -> Data {
        let lines = serializedLines(event, generatedAt: generatedAt)
        var foldedLines: [String] = []
        for line in lines {
            foldedLines.append(fold(line))
        }
        return Data(
            (foldedLines.joined(separator: "\r\n") + "\r\n").utf8
        )
    }

    private static func serializedLines(
        _ event: ICalendarEventDraft,
        generatedAt: Date
    ) -> [String] {
        var lines = [
            "BEGIN:VCALENDAR",
            "VERSION:2.0",
            "PRODID:-//Nagare//Calendar Event//EN",
            "CALSCALE:GREGORIAN",
            "METHOD:PUBLISH",
            "BEGIN:VEVENT",
            "UID:\(escape(event.sourceIdentifier))",
            "DTSTAMP:\(dateTime(generatedAt))"
        ]

        if event.isAllDay {
            lines.append("DTSTART;VALUE=DATE:\(dateOnly(event.scheduledDate))")
            let nextDay = Calendar(identifier: .gregorian).date(
                byAdding: .day,
                value: 1,
                to: event.scheduledDate
            ) ?? event.scheduledDate
            lines.append("DTEND;VALUE=DATE:\(dateOnly(nextDay))")
        } else {
            lines.append("DTSTART:\(dateTime(event.scheduledDate))")
            if let endDate = event.endDate {
                lines.append("DTEND:\(dateTime(endDate))")
            }
        }

        lines.append("SUMMARY:\(escape(event.title))")
        if let notes = event.notes, !notes.isEmpty {
            lines.append("DESCRIPTION:\(escape(notes))")
        }
        lines.append("END:VEVENT")
        lines.append("END:VCALENDAR")
        return lines
    }

    private static func dateTime(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(secondsFromGMT: 0)
        formatter.dateFormat = "yyyyMMdd'T'HHmmss'Z'"
        return formatter.string(from: date)
    }

    private static func dateOnly(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(secondsFromGMT: 0)
        formatter.dateFormat = "yyyyMMdd"
        return formatter.string(from: date)
    }

    private static func escape(_ value: String) -> String {
        value
            .replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "\n", with: "\\n")
            .replacingOccurrences(of: ";", with: "\\;")
            .replacingOccurrences(of: ",", with: "\\,")
    }

    private static func fold(_ line: String) -> String {
        var result = ""
        var byteCount = 0
        for character in line {
            let text = String(character)
            let characterBytes = text.utf8.count
            if byteCount + characterBytes > 75 {
                result += "\r\n "
                byteCount = 1
            }
            result += text
            byteCount += characterBytes
        }
        return result
    }
}
