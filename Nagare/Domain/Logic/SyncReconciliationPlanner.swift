import Foundation

/// Pure, deterministic policy for restoring invariants after asynchronous
/// CloudKit imports. The same immutable graph always yields the same plan.
nonisolated enum SyncReconciliationPlanner {
    static func plan(
        for snapshot: SyncGraphSnapshot
    ) -> SyncReconciliationPlan {
        var report = ReportAccumulator()
        var mergeMutations: [SyncReconciliationMutation] = []

        let projects = deduplicating(snapshot.projects, metadata: \.metadata) {
            SyncProjectSnapshot(metadata: $1)
        }
        mergeMutations += projects.mutations
        report.duplicateProjectsRemoved = projects.removedCount

        let templates = deduplicating(
            snapshot.recurrenceTemplates,
            metadata: \.metadata
        ) { record, metadata in
            SyncRecurrenceTemplateSnapshot(
                metadata: metadata, currentItemID: record.currentItemID,
                currentSequence: record.currentSequence, projectID: record.projectID
            )
        }
        mergeMutations += templates.mutations
        report.duplicateTemplatesRemoved = templates.removedCount

        let todos = deduplicating(snapshot.todos, metadata: \.metadata) { record, metadata in
            SyncTodoSnapshot(
                metadata: metadata, completedAt: record.completedAt,
                recurrenceSequence: record.recurrenceSequence,
                recurrenceTemplateID: record.recurrenceTemplateID, projectID: record.projectID
            )
        }
        mergeMutations += todos.mutations
        report.duplicateTodosRemoved = todos.removedCount

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
            let templateID = template.metadata.semanticID
            let linked = todosByTemplate[templateID] ?? []
            if templates.pendingIDs.contains(templateID)
                || todos.pendingIDs.contains(template.currentItemID)
                || linked.contains(where: { todos.pendingIDs.contains($0.metadata.semanticID) }) {
                if !pending.contains(where: { $0.templateID == templateID }) {
                    pending.append(SyncPendingTemplate(templateID: templateID, reason: .ambiguousDuplicateRecords))
                }
                continue
            }
            reconcileTodoTemplate(
                template,
                linked: linked,
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
            pendingTemplates: pending.count,
            pendingDuplicates: projects.pendingIDs.count + templates.pendingIDs.count + todos.pendingIDs.count
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

        let highest = bySequence[highestSequence, default: []]
        if template.currentSequence == highestSequence {
            let hasCurrent = highest.contains {
                $0.metadata.semanticID == template.currentItemID
                    && $0.completedAt == nil
            }
            guard hasCurrent else {
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
        }
        // A completion can arrive before its successor or template deletion.
        // Do not delete that evidence while the transition is still importing.
        guard highest.allSatisfy({ $0.completedAt == nil }) else {
            pending.append(
                SyncPendingTemplate(
                    templateID: templateID,
                    reason: .noActiveTodoAtCurrentSequence(highestSequence)
                )
            )
            return
        }
        let current = canonicalOccurrence(highest)

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

            let survivor = canonicalOccurrence(occurrences)
            if survivor.completedAt == nil {
                let completionDate = occurrences.compactMap(\.completedAt).min()
                    ?? laterCreationDates[sequence]
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

    // Concurrent devices can hold different template pointers, completion
    // flags, or revisions. A survivor's immutable UUID must decide which
    // physical occurrence is deleted, or replicas can delete each other's.
    private static func canonicalOccurrence(
        _ occurrences: [SyncTodoSnapshot]
    ) -> SyncTodoSnapshot {
        occurrences.max {
            $0.metadata.semanticID.uuidString < $1.metadata.semanticID.uuidString
        }!
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
        metadata: KeyPath<Record, SyncRecordMetadata>,
        replacingMetadata: (Record, SyncRecordMetadata) -> Record
    ) -> (survivors: [Record], mutations: [SyncReconciliationMutation], removedCount: Int, pendingIDs: Set<UUID>) {
        let groups = Dictionary(
            grouping: records,
            by: { $0[keyPath: metadata].semanticID }
        )
        var survivors: [Record] = []
        var mutations: [SyncReconciliationMutation] = []
        var removedCount = 0
        var pendingIDs: Set<UUID> = []

        for semanticID in groups.keys.sorted(by: uuidOrder) {
            guard let group = groups[semanticID] else { continue }
            guard group.count > 1 else {
                survivors += group
                continue
            }
            let physicalIDs = group.compactMap { $0[keyPath: metadata].physicalID }
            guard physicalIDs.count == group.count,
                  Set(physicalIDs).count == group.count else {
                // A store-local object address cannot identify the same
                // survivor on another device. Keep ambiguous rows intact.
                survivors += group
                pendingIDs.insert(semanticID)
                continue
            }
            let survivor = group.max {
                $0[keyPath: metadata].resolvedPhysicalID.uuidString
                    < $1[keyPath: metadata].resolvedPhysicalID.uuidString
            }!
            let content = SyncRecordOrdering.canonical(
                group,
                metadata: metadata
            )
            let identity = survivor[keyPath: metadata]
            let latest = content[keyPath: metadata]
            let mergedMetadata = SyncRecordMetadata(
                reference: identity.reference, semanticID: semanticID,
                physicalID: identity.physicalID, createdAt: latest.createdAt,
                modifiedAt: latest.modifiedAt, stableTieBreaker: latest.stableTieBreaker
            )
            survivors.append(replacingMetadata(content, mergedMetadata))
            let survivorReference = identity.reference
            if latest.reference != survivorReference {
                mutations.append(.copyValues(from: latest.reference, to: survivorReference))
            }
            for duplicate in group
                .filter({ $0[keyPath: metadata].reference != survivorReference })
                .sorted(by: { metadataReferenceOrder(
                    $0[keyPath: metadata],
                    $1[keyPath: metadata]
                ) }) {
                let duplicateReference = duplicate[keyPath: metadata].reference
                removedCount += 1
                mutations.append(
                    .mergeDuplicate(
                        duplicate: duplicateReference,
                        canonical: survivorReference
                    )
                )
            }
        }

        return (survivors, mutations, removedCount, pendingIDs)
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
