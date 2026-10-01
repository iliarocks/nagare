import Foundation

/// Pure, deterministic policy for restoring invariants after asynchronous
/// CloudKit imports. The same immutable graph always yields the same plan.
nonisolated enum SyncReconciliationPlanner {
    static func plan(
        for snapshot: SyncGraphSnapshot
    ) -> SyncReconciliationPlan {
        var report = ReportAccumulator()
        var mergeMutations: [SyncReconciliationMutation] = []

        let projects = deduplicating(snapshot.projects, metadata: \.metadata)
        mergeMutations += projects.mutations
        report.duplicateProjectsRemoved = projects.mutations.count

        let templates = deduplicating(
            snapshot.recurrenceTemplates,
            metadata: \.metadata
        )
        mergeMutations += templates.mutations
        report.duplicateTemplatesRemoved = templates.mutations.count

        let todos = deduplicating(snapshot.todos, metadata: \.metadata)
        mergeMutations += todos.mutations
        report.duplicateTodosRemoved = todos.mutations.count

        var recurrenceMutations: [SyncReconciliationMutation] = []
        var pending: [SyncPendingTemplate] = []
        let todosByID = Dictionary(
            grouping: todos.survivors,
            by: { $0.metadata.semanticID }
        )
        let todosByTemplate = Dictionary(
            grouping: todos.survivors,
            by: \.recurrenceTemplateID
        )

        for template in templates.survivors.sorted(by: semanticIDOrder) {
            reconcileTodoTemplate(
                template,
                linked: todosByTemplate[template.metadata.semanticID] ?? [],
                matchingCurrent: (todosByID[template.currentItemID] ?? []).filter {
                    $0.recurrenceSequence == template.currentSequence
                },
                mutations: &recurrenceMutations,
                pending: &pending,
                report: &report
            )
        }

        let removedReferences = Set(
            (mergeMutations + recurrenceMutations).compactMap { mutation in
                switch mutation {
                case .mergeDuplicate(let duplicate, _): duplicate
                case .delete(let record): record
                default: nil
                }
            }
        )
        let assignments = snapshot.allMetadata
            .filter { $0.physicalID == nil }
            .sorted(by: metadataReferenceOrder)
            .map {
                SyncReconciliationMutation.assignPhysicalID(
                    record: $0.reference,
                    physicalID: $0.semanticID
                )
            }

        let removedWithMissingIdentity = snapshot.allMetadata.filter {
            $0.physicalID == nil
                && removedReferences.contains($0.reference)
        }.count
        let reportSnapshot = SyncReconciliationReport(
            duplicateProjectsRemoved: report.duplicateProjectsRemoved,
            duplicateTodosRemoved: report.duplicateTodosRemoved,
            duplicateTemplatesRemoved: report.duplicateTemplatesRemoved,
            recurrenceConflictsRepaired: report.recurrenceConflictsRepaired,
            recurrenceLinksRepaired: report.recurrenceLinksRepaired,
            syncRecordIDsAssigned:
                assignments.count - removedWithMissingIdentity,
            pendingTemplates: pending.count
        )

        return SyncReconciliationPlan(
            mutations: assignments + mergeMutations + recurrenceMutations,
            pendingTemplates: pending.sorted {
                $0.templateID.uuidString < $1.templateID.uuidString
            },
            report: reportSnapshot
        )
    }

    private static func reconcileTodoTemplate(
        _ template: SyncRecurrenceTemplateSnapshot,
        linked: [SyncTodoSnapshot],
        matchingCurrent: [SyncTodoSnapshot],
        mutations: inout [SyncReconciliationMutation],
        pending: inout [SyncPendingTemplate],
        report: inout ReportAccumulator
    ) {
        let templateID = template.metadata.semanticID
        if matchingCurrent.contains(where: {
            $0.recurrenceTemplateID != nil
                && $0.recurrenceTemplateID != templateID
        }) {
            pending.append(
                SyncPendingTemplate(
                    templateID: templateID,
                    reason: .currentOccurrenceLinkedElsewhere(
                        id: template.currentItemID
                    )
                )
            )
            return
        }

        let associated = linked + matchingCurrent.filter {
            $0.recurrenceTemplateID == nil
        }
        let bySequence = Dictionary(
            grouping: associated,
            by: \.recurrenceSequence
        )
        let sequences = bySequence.keys.compactMap { $0 }.sorted()
        guard let highestSequence = sequences.last else {
            pending.append(
                SyncPendingTemplate(
                    templateID: templateID,
                    reason: .noSequencedOccurrences
                )
            )
            return
        }
        guard template.currentSequence <= highestSequence else {
            pending.append(
                SyncPendingTemplate(
                    templateID: templateID,
                    reason: .waitingForCurrentSequence(
                        expected: template.currentSequence,
                        highestAvailable: highestSequence
                    )
                )
            )
            return
        }

        let current: SyncTodoSnapshot
        if template.currentSequence == highestSequence {
            let candidates = bySequence[highestSequence, default: []]
                .filter {
                    $0.metadata.semanticID == template.currentItemID
                        && $0.completedAt == nil
                }
            guard !candidates.isEmpty else {
                let hasCompletedCurrent = matchingCurrent.contains {
                    $0.completedAt != nil
                }
                pending.append(
                    SyncPendingTemplate(
                        templateID: templateID,
                        reason: hasCompletedCurrent
                            ? .noActiveTodoAtCurrentSequence(highestSequence)
                            : .missingCurrentOccurrence(
                                id: template.currentItemID,
                                sequence: template.currentSequence
                            )
                    )
                )
                return
            }
            current = SyncRecordOrdering.canonical(
                candidates,
                metadata: \.metadata
            )
        } else {
            let activeHighest = bySequence[highestSequence, default: []]
                .filter { $0.completedAt == nil }
            guard !activeHighest.isEmpty else {
                pending.append(
                    SyncPendingTemplate(
                        templateID: templateID,
                        reason: .noActiveTodoAtCurrentSequence(highestSequence)
                    )
                )
                return
            }
            current = SyncRecordOrdering.canonical(
                activeHighest,
                metadata: \.metadata
            )
        }

        attachTodoIfNeeded(
            current,
            to: template,
            mutations: &mutations,
            report: &report
        )

        // A historical occurrence completes at the earliest creation of any
        // later sequence, even when imported creation dates are out of order.
        var laterCreationDates: [Int: Date] = [:]
        var earliestLaterCreation: Date?
        for sequence in sequences.reversed() {
            laterCreationDates[sequence] = earliestLaterCreation
            for occurrence in bySequence[sequence, default: []] {
                let createdAt = occurrence.metadata.createdAt
                earliestLaterCreation = earliestLaterCreation.map {
                    min($0, createdAt)
                } ?? createdAt
            }
        }

        for sequence in sequences {
            let occurrences = bySequence[sequence, default: []]
                .sorted {
                    metadataReferenceOrder($0.metadata, $1.metadata)
                }

            if sequence == highestSequence {
                for duplicate in occurrences
                where duplicate.metadata.reference != current.metadata.reference {
                    mutations.append(.delete(record: duplicate.metadata.reference))
                    report.recurrenceConflictsRepaired += 1
                }
                continue
            }

            let completed = occurrences.filter { $0.completedAt != nil }
            let survivor = SyncRecordOrdering.canonical(
                completed.isEmpty ? occurrences : completed,
                metadata: \.metadata
            )
            if survivor.completedAt == nil {
                let completionDate = laterCreationDates[sequence]
                    ?? template.metadata.revisionDate
                mutations.append(
                    .completeTodo(
                        record: survivor.metadata.reference,
                        completedAt: completionDate
                    )
                )
                report.recurrenceConflictsRepaired += 1
            }
            for duplicate in occurrences
            where duplicate.metadata.reference != survivor.metadata.reference {
                mutations.append(.delete(record: duplicate.metadata.reference))
                report.recurrenceConflictsRepaired += 1
            }
        }

        if template.currentSequence != highestSequence
            || template.currentItemID != current.metadata.semanticID {
            mutations.append(
                .updateTemplate(
                    record: template.metadata.reference,
                    currentItemID: current.metadata.semanticID,
                    currentSequence: highestSequence
                )
            )
            report.recurrenceConflictsRepaired += 1
        }
    }

    private static func attachTodoIfNeeded(
        _ todo: SyncTodoSnapshot,
        to template: SyncRecurrenceTemplateSnapshot,
        mutations: inout [SyncReconciliationMutation],
        report: inout ReportAccumulator
    ) {
        guard todo.recurrenceTemplateID == nil else { return }
        mutations.append(
            .attachTodo(
                todo: todo.metadata.reference,
                template: template.metadata.reference
            )
        )
        report.recurrenceLinksRepaired += 1
    }

    private static func deduplicating<Record>(
        _ records: [Record],
        metadata: KeyPath<Record, SyncRecordMetadata>
    ) -> (survivors: [Record], mutations: [SyncReconciliationMutation]) {
        let groups = Dictionary(
            grouping: records,
            by: { $0[keyPath: metadata].semanticID }
        )
        var removed: Set<SyncRecordReference> = []
        var mutations: [SyncReconciliationMutation] = []

        for semanticID in groups.keys.sorted(by: uuidOrder) {
            guard let group = groups[semanticID], group.count > 1 else {
                continue
            }
            let survivor = SyncRecordOrdering.canonical(
                group,
                metadata: metadata
            )
            let survivorReference = survivor[keyPath: metadata].reference
            for duplicate in group
                .filter({ $0[keyPath: metadata].reference != survivorReference })
                .sorted(by: { metadataReferenceOrder(
                    $0[keyPath: metadata],
                    $1[keyPath: metadata]
                ) }) {
                let duplicateReference = duplicate[keyPath: metadata].reference
                removed.insert(duplicateReference)
                mutations.append(
                    .mergeDuplicate(
                        duplicate: duplicateReference,
                        canonical: survivorReference
                    )
                )
            }
        }

        return (
            records.filter { !removed.contains($0[keyPath: metadata].reference) },
            mutations
        )
    }

    private static func semanticIDOrder(
        _ first: SyncRecurrenceTemplateSnapshot,
        _ second: SyncRecurrenceTemplateSnapshot
    ) -> Bool {
        uuidOrder(first.metadata.semanticID, second.metadata.semanticID)
    }

    private static func uuidOrder(_ first: UUID, _ second: UUID) -> Bool {
        first.uuidString < second.uuidString
    }

    private static func metadataReferenceOrder(
        _ first: SyncRecordMetadata,
        _ second: SyncRecordMetadata
    ) -> Bool {
        if first.reference.kind.rawValue != second.reference.kind.rawValue {
            return first.reference.kind.rawValue < second.reference.kind.rawValue
        }
        return first.reference.localID < second.reference.localID
    }

    private struct ReportAccumulator {
        var duplicateProjectsRemoved = 0
        var duplicateTodosRemoved = 0
        var duplicateTemplatesRemoved = 0
        var recurrenceConflictsRepaired = 0
        var recurrenceLinksRepaired = 0
    }
}
