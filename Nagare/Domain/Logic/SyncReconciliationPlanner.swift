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

        let events = deduplicating(snapshot.events, metadata: \.metadata)
        mergeMutations += events.mutations
        report.duplicateEventsRemoved = events.mutations.count

        var recurrenceMutations: [SyncReconciliationMutation] = []
        var pending: [SyncPendingTemplate] = []

        for template in templates.survivors.sorted(by: semanticIDOrder) {
            switch template.itemTypeRawValue {
            case "todo":
                reconcileTodoTemplate(
                    template,
                    todos: todos.survivors,
                    mutations: &recurrenceMutations,
                    pending: &pending,
                    report: &report
                )
            case "event":
                reconcileEventTemplate(
                    template,
                    events: events.survivors,
                    mutations: &recurrenceMutations,
                    pending: &pending,
                    report: &report
                )
            default:
                pending.append(
                    SyncPendingTemplate(
                        templateID: template.metadata.semanticID,
                        reason: .unknownItemType(template.itemTypeRawValue)
                    )
                )
            }
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
            duplicateEventsRemoved: report.duplicateEventsRemoved,
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
            transactionDate: snapshot.allMetadata
                .map(\.revisionDate)
                .max() ?? Date(timeIntervalSince1970: 0),
            report: reportSnapshot
        )
    }

    private static func reconcileTodoTemplate(
        _ template: SyncRecurrenceTemplateSnapshot,
        todos: [SyncTodoSnapshot],
        mutations: inout [SyncReconciliationMutation],
        pending: inout [SyncPendingTemplate],
        report: inout ReportAccumulator
    ) {
        let templateID = template.metadata.semanticID
        let matchingCurrent = todos.filter {
            $0.metadata.semanticID == template.currentItemID
                && $0.recurrenceSequence == template.currentSequence
        }
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

        let associated = todos.filter {
            $0.recurrenceTemplateID == templateID
                || ($0.metadata.semanticID == template.currentItemID
                    && $0.recurrenceSequence == template.currentSequence
                    && $0.recurrenceTemplateID == nil)
        }
        let sequenced = associated.compactMap { todo in
            todo.recurrenceSequence.map { (sequence: $0, record: todo) }
        }
        guard let highestSequence = sequenced.map(\.sequence).max() else {
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
            let candidates = sequenced
                .filter {
                    $0.sequence == highestSequence
                        && $0.record.metadata.semanticID
                            == template.currentItemID
                        && $0.record.completedAt == nil
                }
                .map(\.record)
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
            let activeHighest = sequenced
                .filter {
                    $0.sequence == highestSequence
                        && $0.record.completedAt == nil
                }
                .map(\.record)
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

        for sequence in Set(sequenced.map(\.sequence)).sorted() {
            let occurrences = sequenced
                .filter { $0.sequence == sequence }
                .map(\.record)
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
                let completionDate = sequenced
                    .filter { $0.sequence > sequence }
                    .map { $0.record.metadata.createdAt }
                    .min() ?? template.metadata.revisionDate
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

    private static func reconcileEventTemplate(
        _ template: SyncRecurrenceTemplateSnapshot,
        events: [SyncEventSnapshot],
        mutations: inout [SyncReconciliationMutation],
        pending: inout [SyncPendingTemplate],
        report: inout ReportAccumulator
    ) {
        let templateID = template.metadata.semanticID
        let matchingCurrent = events.filter {
            $0.metadata.semanticID == template.currentItemID
                && $0.recurrenceSequence == template.currentSequence
        }
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

        let associated = events.filter {
            $0.recurrenceTemplateID == templateID
                || ($0.metadata.semanticID == template.currentItemID
                    && $0.recurrenceSequence == template.currentSequence
                    && $0.recurrenceTemplateID == nil)
        }
        let sequenced = associated.compactMap { event in
            event.recurrenceSequence.map { (sequence: $0, record: event) }
        }
        guard let highestSequence = sequenced.map(\.sequence).max() else {
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

        let current: SyncEventSnapshot
        if template.currentSequence == highestSequence {
            let candidates = sequenced
                .filter {
                    $0.sequence == highestSequence
                        && $0.record.metadata.semanticID
                            == template.currentItemID
                }
                .map(\.record)
            guard !candidates.isEmpty else {
                pending.append(
                    SyncPendingTemplate(
                        templateID: templateID,
                        reason: .missingCurrentOccurrence(
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
            current = SyncRecordOrdering.canonical(
                sequenced
                    .filter { $0.sequence == highestSequence }
                    .map(\.record),
                metadata: \.metadata
            )
        }

        attachEventIfNeeded(
            current,
            to: template,
            mutations: &mutations,
            report: &report
        )

        for occurrence in sequenced.map(\.record).sorted(by: {
            metadataReferenceOrder($0.metadata, $1.metadata)
        })
        where occurrence.metadata.reference != current.metadata.reference {
            mutations.append(.delete(record: occurrence.metadata.reference))
            report.recurrenceConflictsRepaired += 1
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

    private static func attachEventIfNeeded(
        _ event: SyncEventSnapshot,
        to template: SyncRecurrenceTemplateSnapshot,
        mutations: inout [SyncReconciliationMutation],
        report: inout ReportAccumulator
    ) {
        guard event.recurrenceTemplateID == nil else { return }
        mutations.append(
            .attachEvent(
                event: event.metadata.reference,
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
        var duplicateEventsRemoved = 0
        var duplicateTemplatesRemoved = 0
        var recurrenceConflictsRepaired = 0
        var recurrenceLinksRepaired = 0
    }
}
