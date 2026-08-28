import Foundation

/// Projects recurrence values without touching SwiftData objects. A missing
/// current occurrence is normal during an out-of-order CloudKit import, so it
/// is returned as pending input rather than thrown as corruption.
nonisolated enum RecurrenceProjectionLogic {
    static func generate(
        from input: RecurrenceProjectionInput,
        starting startDate: Date,
        through horizon: Date,
        calendar: Calendar
    ) -> RecurrenceProjectionResult {
        var items: [ProjectedRecurrenceItem] = []
        var issues: [RecurrenceProjectionIssue] = []

        for template in canonicalTemplates(input.templates) {
            let currentCandidates = input.occurrences.filter {
                $0.metadata.semanticID == template.currentItemID
                    && $0.recurrenceSequence == template.currentSequence
                    && ($0.recurrenceTemplateID == nil
                        || $0.recurrenceTemplateID
                            == template.metadata.semanticID)
                    && $0.completedAt == nil
            }
            guard !currentCandidates.isEmpty else {
                issues.append(
                    issue(
                        for: template,
                        kind: .pendingCurrentOccurrence(
                            id: template.currentItemID,
                            sequence: template.currentSequence
                        )
                    )
                )
                continue
            }
            let current = SyncRecordOrdering.canonical(
                currentCandidates,
                metadata: \.metadata
            )

            let rule: RecurrenceRule
            do {
                rule = try recurrenceRule(for: template, calendar: calendar)
            } catch {
                issues.append(
                    issue(
                        for: template,
                        kind: .invalidRule(String(describing: error))
                    )
                )
                continue
            }

            let dates: [Date]
            do {
                dates = try RecurrenceCalculator.virtualDates(
                    after: current.scheduledDate,
                    using: rule,
                    absoluteThrough: horizon,
                    calendar: calendar
                )
            } catch {
                issues.append(
                    issue(
                        for: template,
                        kind: .invalidRule(String(describing: error))
                    )
                )
                continue
            }

            let firstVisibleDay = calendar.startOfDay(for: startDate)
            for projectedDate in dates {
                let day = calendar.startOfDay(for: projectedDate)
                guard day >= firstVisibleDay else { continue }
                do {
                    let start = try template.startTimeSeconds.map {
                        try applying(seconds: $0, to: day, calendar: calendar)
                    }
                    let end = try template.endTimeSeconds.map {
                        try applying(seconds: $0, to: day, calendar: calendar)
                    }
                    items.append(
                        ProjectedRecurrenceItem(
                            templateReference: template.metadata.reference,
                            templateID: template.metadata.semanticID,
                            date: day,
                            startDate: start,
                            endDate: end,
                            order: current.order
                        )
                    )
                } catch let failure as ProjectionFailure {
                    issues.append(issue(for: template, kind: failure.kind))
                } catch {
                    issues.append(
                        issue(for: template, kind: .dateCalculationFailed)
                    )
                }
            }
        }

        return RecurrenceProjectionResult(
            items: items.sorted {
                if $0.date != $1.date { return $0.date < $1.date }
                if $0.templateID != $1.templateID {
                    return $0.templateID.uuidString
                        < $1.templateID.uuidString
                }
                return $0.templateReference.localID
                    < $1.templateReference.localID
            },
            issues: issues.sorted {
                $0.templateID.uuidString < $1.templateID.uuidString
            }
        )
    }

    private static func canonicalTemplates(
        _ templates: [RecurrenceProjectionTemplateSnapshot]
    ) -> [RecurrenceProjectionTemplateSnapshot] {
        let groups = Dictionary(
            grouping: templates,
            by: { $0.metadata.semanticID }
        )
        return groups.keys
            .sorted { $0.uuidString < $1.uuidString }
            .compactMap { semanticID in
                guard let group = groups[semanticID] else { return nil }
                return SyncRecordOrdering.canonical(
                    group,
                    metadata: \.metadata
                )
            }
    }

    private static func recurrenceRule(
        for template: RecurrenceProjectionTemplateSnapshot,
        calendar: Calendar
    ) throws -> RecurrenceRule {
        guard let mode = RecurrenceMode(rawValue: template.modeRawValue) else {
            throw RuleFailure.invalidMode(template.modeRawValue)
        }
        guard let unit = RecurrenceUnit(rawValue: template.unitRawValue) else {
            throw RuleFailure.invalidUnit(template.unitRawValue)
        }

        switch mode {
        case .relative:
            return try RecurrenceRule.relative(
                every: template.interval,
                unit: unit
            )
        case .absolute:
            guard let reference = template.reference else {
                throw RuleFailure.missingReference
            }
            return try RecurrenceRule.absolute(
                every: template.interval,
                unit: unit,
                anchors: template.anchors,
                reference: reference,
                calendar: calendar
            )
        }
    }

    private static func applying(
        seconds: Int,
        to day: Date,
        calendar: Calendar
    ) throws -> Date {
        guard (0..<86_400).contains(seconds) else {
            throw ProjectionFailure(kind: .invalidTime(seconds))
        }
        let hour = seconds / 3_600
        let minute = seconds % 3_600 / 60
        let second = seconds % 60
        guard let result = calendar.date(
            bySettingHour: hour,
            minute: minute,
            second: second,
            of: day
        ) else {
            throw ProjectionFailure(kind: .dateCalculationFailed)
        }
        return result
    }

    private static func issue(
        for template: RecurrenceProjectionTemplateSnapshot,
        kind: RecurrenceProjectionIssueKind
    ) -> RecurrenceProjectionIssue {
        RecurrenceProjectionIssue(
            templateID: template.metadata.semanticID,
            kind: kind
        )
    }

    private struct ProjectionFailure: Error {
        let kind: RecurrenceProjectionIssueKind
    }

    private enum RuleFailure: Error {
        case invalidMode(String)
        case invalidUnit(String)
        case missingReference
    }
}
