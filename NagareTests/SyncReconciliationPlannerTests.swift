import Foundation
import Testing
@testable import Nagare

struct SyncReconciliationPlannerTests {
    private let templateID = UUID(
        uuidString: "10000000-0000-0000-0000-000000000001"
    )!
    private let currentID = UUID(
        uuidString: "20000000-0000-0000-0000-000000000001"
    )!
    private let competingID = UUID(
        uuidString: "20000000-0000-0000-0000-000000000002"
    )!
    private let laterID = UUID(
        uuidString: "20000000-0000-0000-0000-000000000003"
    )!
    private let timestamp = Date(timeIntervalSince1970: 1_750_000_000)

    @Test func legacyPhysicalIdentityIsDeterministic() {
        let semanticID = UUID(
            uuidString: "30000000-0000-0000-0000-000000000001"
        )!
        let todo = SyncTodoSnapshot(
            metadata: SyncRecordMetadata(
                reference: SyncRecordReference(
                    kind: .todo,
                    localID: "legacy"
                ),
                semanticID: semanticID,
                physicalID: nil,
                createdAt: timestamp,
                modifiedAt: nil,
                stableTieBreaker: ["legacy"]
            ),
            completedAt: nil,
            recurrenceSequence: nil,
            recurrenceTemplateID: nil,
            projectID: nil
        )

        let plan = SyncReconciliationPlanner.plan(
            for: graph(todos: [todo])
        )

        #expect(plan.mutations == [
            .assignPhysicalID(
                record: todo.metadata.reference,
                physicalID: semanticID
            )
        ])
    }

    @Test func replicatedPhysicalIdentityBreaksExactTimestampTie() {
        let semanticID = UUID(
            uuidString: "30000000-0000-0000-0000-000000000002"
        )!
        let low = todo(
            id: semanticID,
            localID: "local-z",
            physicalID: UUID(
                uuidString: "40000000-0000-0000-0000-000000000001"
            )!
        )
        let high = todo(
            id: semanticID,
            localID: "local-a",
            physicalID: UUID(
                uuidString: "40000000-0000-0000-0000-000000000002"
            )!
        )

        let plan = SyncReconciliationPlanner.plan(
            for: graph(todos: [low, high])
        )

        #expect(plan.mutations == [
            .mergeDuplicate(
                duplicate: low.metadata.reference,
                canonical: high.metadata.reference
            )
        ])
    }

    @Test func duplicateReplicasRetainTheSamePhysicalRowDespiteStaleContent() {
        for newestPhysicalID in [currentID, competingID] {
            let rows = [currentID, competingID].map { physicalID in
                todo(id: laterID, localID: physicalID.uuidString, physicalID: physicalID,
                     modifiedAt: timestamp.addingTimeInterval(physicalID == newestPhysicalID ? 10 : 0))
            }
            let plan = SyncReconciliationPlanner.plan(for: graph(todos: rows))
            let source = rows[0].metadata.reference
            let survivor = rows[1].metadata.reference
            let copy: [SyncReconciliationMutation] = newestPhysicalID == currentID
                ? [.copyValues(from: source, to: survivor)] : []
            #expect(plan.mutations == copy + [.mergeDuplicate(duplicate: source, canonical: survivor)])
            #expect(plan.report.duplicateTodosRemoved == 1)
        }
    }

    @Test func ambiguousPhysicalIdentitiesRemainIntactAndBlockRecurrenceCleanup() {
        for physicalID in [nil, Optional(currentID)] {
            let rows = ["local-a", "local-b"].map { localID in
                SyncTodoSnapshot(metadata: SyncRecordMetadata(
                    reference: SyncRecordReference(kind: .todo, localID: localID), semanticID: currentID,
                    physicalID: physicalID, createdAt: timestamp, modifiedAt: timestamp, stableTieBreaker: []
                ), completedAt: nil, recurrenceSequence: 0, recurrenceTemplateID: templateID, projectID: nil)
            }
            let plan = SyncReconciliationPlanner.plan(for: graph(
                templates: [todoTemplate(currentItemID: currentID, currentSequence: 0)], todos: rows
            ))
            #expect(plan.report.pendingDuplicates == 1)
            #expect(plan.report.duplicateTodosRemoved == 0)
            #expect(plan.pendingTemplates == [SyncPendingTemplate(templateID: templateID, reason: .ambiguousDuplicateRecords)])
            #expect(plan.mutations.allSatisfy {
                if case .assignPhysicalID = $0 { return true }
                return false
            })
        }
    }

    @Test func recurrenceRepairUsesContentCopiedOntoTheFixedTemplateSurvivor() {
        let latest = SyncRecurrenceTemplateSnapshot(metadata: metadata(
            kind: .recurrenceTemplate, localID: "latest", semanticID: templateID,
            physicalID: currentID, modifiedAt: timestamp.addingTimeInterval(10)
        ), currentItemID: competingID, currentSequence: 1, projectID: nil)
        let fixed = SyncRecurrenceTemplateSnapshot(metadata: metadata(
            kind: .recurrenceTemplate, localID: "fixed", semanticID: templateID, physicalID: competingID
        ), currentItemID: laterID, currentSequence: 0, projectID: nil)
        let current = todo(id: competingID, localID: "current", sequence: 1, templateID: templateID)
        let plan = SyncReconciliationPlanner.plan(for: graph(templates: [latest, fixed], todos: [current]))
        #expect(plan.pendingTemplates.isEmpty)
        #expect(plan.mutations == [
            .copyValues(from: latest.metadata.reference, to: fixed.metadata.reference),
            .mergeDuplicate(duplicate: latest.metadata.reference, canonical: fixed.metadata.reference)
        ])
    }

    @Test func templateFirstImportIsPendingAndNonDestructive() {
        let template = todoTemplate(
            currentItemID: currentID,
            currentSequence: 1
        )
        let competing = todo(
            id: competingID,
            localID: "competing",
            sequence: 1,
            templateID: templateID
        )

        let plan = SyncReconciliationPlanner.plan(
            for: graph(templates: [template], todos: [competing])
        )

        #expect(plan.mutations.isEmpty)
        #expect(plan.pendingTemplates == [
            SyncPendingTemplate(
                templateID: templateID,
                reason: .missingCurrentOccurrence(
                    id: currentID,
                    sequence: 1
                )
            )
        ])
    }

    @Test func missingInverseRelationshipProducesOnlyAnAttachPlan() {
        let template = todoTemplate(
            currentItemID: currentID,
            currentSequence: 0
        )
        let current = todo(
            id: currentID,
            localID: "current",
            sequence: 0,
            templateID: nil
        )

        let plan = SyncReconciliationPlanner.plan(
            for: graph(templates: [template], todos: [current])
        )

        #expect(plan.pendingTemplates.isEmpty)
        #expect(plan.mutations == [
            .attachTodo(
                todo: current.metadata.reference,
                template: template.metadata.reference
            )
        ])
    }

    @Test func competingTodoSuccessorsChooseImmutableIdentity() {
        let template = todoTemplate(
            currentItemID: currentID,
            currentSequence: 1
        )
        let original = todo(
            id: laterID,
            localID: "original",
            completedAt: timestamp,
            sequence: 0,
            templateID: templateID
        )
        let pointed = todo(
            id: currentID,
            localID: "pointed",
            sequence: 1,
            templateID: templateID
        )
        let competing = todo(
            id: competingID,
            localID: "competing",
            sequence: 1,
            templateID: templateID
        )

        let plan = SyncReconciliationPlanner.plan(
            for: graph(
                templates: [template],
                todos: [original, pointed, competing]
            )
        )

        #expect(plan.pendingTemplates.isEmpty)
        #expect(plan.mutations == [
            .delete(record: pointed.metadata.reference),
            .updateTemplate(
                record: template.metadata.reference,
                currentItemID: competingID,
                currentSequence: 1
            )
        ])
    }

    @Test func interleavedSuccessorImportsCannotMakeReplicasDeleteEachOther() {
        var deleted: Set<SyncRecordReference> = []
        for localCurrentID in [currentID, competingID] {
            let template = todoTemplate(currentItemID: localCurrentID, currentSequence: 1)
            // Each replica receives both successors before the other template
            // update, and still considers its own successor the newest edit.
            let occurrences = [currentID, competingID].map { id in
                todo(
                    id: id, localID: id.uuidString, sequence: 1,
                    templateID: templateID,
                    modifiedAt: timestamp.addingTimeInterval(id == localCurrentID ? 10 : 0)
                )
            }
            let plan = SyncReconciliationPlanner.plan(
                for: graph(templates: [template], todos: occurrences)
            )
            #expect(plan.pendingTemplates.isEmpty)
            let removals = plan.mutations.compactMap { mutation -> SyncRecordReference? in
                if case .delete(let record) = mutation { return record }
                return nil
            }
            #expect(removals.map(\.localID) == [currentID.uuidString])
            deleted.formUnion(removals)
        }
        let survivor = todo(id: competingID, localID: competingID.uuidString, sequence: 1, templateID: templateID)
        #expect(!deleted.contains(survivor.metadata.reference))
        let converged = SyncReconciliationPlanner.plan(for: graph(
            templates: [todoTemplate(currentItemID: competingID, currentSequence: 1)],
            todos: [survivor]
        ))
        #expect(converged.mutations.isEmpty)
        #expect(converged.pendingTemplates.isEmpty)
    }

    @Test func completedCompetingSuccessorWaitsForItsLaterSequence() {
        let template = todoTemplate(currentItemID: currentID, currentSequence: 1)
        let current = todo(id: currentID, localID: "current", sequence: 1, templateID: templateID)
        let completed = todo(id: competingID, localID: "completed", completedAt: timestamp,
                             sequence: 1, templateID: templateID)
        let plan = SyncReconciliationPlanner.plan(for: graph(templates: [template], todos: [current, completed]))
        #expect(plan.mutations.isEmpty)
        #expect(plan.pendingTemplates == [SyncPendingTemplate(
            templateID: templateID, reason: .noActiveTodoAtCurrentSequence(1)
        )])
    }

    @Test func historicalSurvivorDoesNotDependOnWhichCompletionArrivesFirst() {
        let template = todoTemplate(currentItemID: laterID, currentSequence: 2)
        let next = todo(id: laterID, localID: "next", sequence: 2, templateID: templateID,
                        createdAt: timestamp.addingTimeInterval(10))
        for completedID in [currentID, competingID] {
            let occurrences = [currentID, competingID].map { id in
                todo(id: id, localID: id.uuidString, completedAt: id == completedID ? timestamp : nil,
                     sequence: 1, templateID: templateID)
            }
            let plan = SyncReconciliationPlanner.plan(for: graph(templates: [template], todos: occurrences + [next]))
            #expect(plan.pendingTemplates.isEmpty)
            #expect(plan.mutations.contains(.delete(record: occurrences[0].metadata.reference)))
            #expect(!plan.mutations.contains(.delete(record: occurrences[1].metadata.reference)))
            if completedID == currentID {
                #expect(plan.mutations.contains(.completeTodo(record: occurrences[1].metadata.reference, completedAt: timestamp)))
            }
        }
    }

    @Test func newerTemplateSequenceNeverRegressesToAnOlderImportedOccurrence() {
        let template = todoTemplate(currentItemID: laterID, currentSequence: 2)
        let earlier = todo(id: currentID, localID: "earlier", sequence: 1, templateID: templateID)
        let plan = SyncReconciliationPlanner.plan(for: graph(templates: [template], todos: [earlier]))
        #expect(plan.mutations.isEmpty)
        #expect(plan.pendingTemplates == [SyncPendingTemplate(
            templateID: templateID, reason: .waitingForCurrentSequence(expected: 2, highestAvailable: 1)
        )])
    }

    @Test func inputPermutationDoesNotChangeThePlan() {
        let template = todoTemplate(
            currentItemID: currentID,
            currentSequence: 1
        )
        let original = todo(
            id: laterID,
            localID: "original",
            completedAt: timestamp,
            sequence: 0,
            templateID: templateID
        )
        let pointed = todo(
            id: currentID,
            localID: "pointed",
            sequence: 1,
            templateID: templateID
        )
        let competing = todo(
            id: competingID,
            localID: "competing",
            sequence: 1,
            templateID: templateID
        )
        let forward = graph(
            templates: [template],
            todos: [original, pointed, competing]
        )
        let reversed = graph(
            templates: [template],
            todos: [competing, pointed, original]
        )

        #expect(
            SyncReconciliationPlanner.plan(for: forward)
                == SyncReconciliationPlanner.plan(for: reversed)
        )
    }

    @Test func historicalCompletionUsesEarliestCreationAcrossAllLaterSequences() {
        let template = todoTemplate(currentItemID: currentID, currentSequence: 2)
        let first = todo(
            id: laterID, localID: "first", sequence: 0,
            templateID: templateID, createdAt: timestamp
        )
        let second = todo(
            id: competingID, localID: "second", sequence: 1,
            templateID: templateID, createdAt: timestamp.addingTimeInterval(200)
        )
        let current = todo(
            id: currentID, localID: "current", sequence: 2,
            templateID: templateID, createdAt: timestamp.addingTimeInterval(100)
        )
        let expected: [SyncReconciliationMutation] = [
            .completeTodo(
                record: first.metadata.reference,
                completedAt: current.metadata.createdAt
            ),
            .completeTodo(
                record: second.metadata.reference,
                completedAt: current.metadata.createdAt
            )
        ]
        for occurrences in [[first, second, current], [current, first, second]] {
            let plan = SyncReconciliationPlanner.plan(
                for: graph(templates: [template], todos: occurrences)
            )
            #expect(plan.mutations == expected)
            #expect(plan.pendingTemplates.isEmpty)
        }
    }

    @Test func currentOccurrenceLinkedElsewhereRemainsPending() {
        let template = todoTemplate(currentItemID: currentID, currentSequence: 0)
        let current = todo(
            id: currentID, localID: "current", sequence: 0,
            templateID: competingID
        )
        let plan = SyncReconciliationPlanner.plan(
            for: graph(templates: [template], todos: [current])
        )
        #expect(plan.mutations.isEmpty)
        #expect(plan.pendingTemplates == [
            SyncPendingTemplate(
                templateID: templateID,
                reason: .currentOccurrenceLinkedElsewhere(id: currentID)
            )
        ])
    }

    private func graph(
        templates: [SyncRecurrenceTemplateSnapshot] = [],
        todos: [SyncTodoSnapshot] = []
    ) -> SyncGraphSnapshot {
        SyncGraphSnapshot(
            projects: [],
            recurrenceTemplates: templates,
            todos: todos
        )
    }

    private func todoTemplate(
        currentItemID: UUID,
        currentSequence: Int
    ) -> SyncRecurrenceTemplateSnapshot {
        template(
            currentItemID: currentItemID,
            currentSequence: currentSequence
        )
    }

    private func template(
        currentItemID: UUID,
        currentSequence: Int
    ) -> SyncRecurrenceTemplateSnapshot {
        SyncRecurrenceTemplateSnapshot(
            metadata: metadata(
                kind: .recurrenceTemplate,
                localID: "template",
                semanticID: templateID
            ),
            currentItemID: currentItemID,
            currentSequence: currentSequence,
            projectID: nil
        )
    }

    private func todo(
        id: UUID,
        localID: String,
        physicalID: UUID? = nil,
        completedAt: Date? = nil,
        sequence: Int? = nil,
        templateID: UUID? = nil,
        createdAt: Date? = nil,
        modifiedAt: Date? = nil
    ) -> SyncTodoSnapshot {
        SyncTodoSnapshot(
            metadata: metadata(
                kind: .todo,
                localID: localID,
                semanticID: id,
                physicalID: physicalID ?? id,
                createdAt: createdAt,
                modifiedAt: modifiedAt
            ),
            completedAt: completedAt,
            recurrenceSequence: sequence,
            recurrenceTemplateID: templateID,
            projectID: nil
        )
    }

    private func metadata(
        kind: SyncEntityKind,
        localID: String,
        semanticID: UUID,
        physicalID: UUID? = nil,
        createdAt: Date? = nil,
        modifiedAt: Date? = nil
    ) -> SyncRecordMetadata {
        SyncRecordMetadata(
            reference: SyncRecordReference(kind: kind, localID: localID),
            semanticID: semanticID,
            physicalID: physicalID ?? semanticID,
            createdAt: createdAt ?? timestamp,
            modifiedAt: modifiedAt ?? timestamp,
            stableTieBreaker: [localID]
        )
    }
}

@MainActor
struct SyncReconciliationOrchestratorTests {
    @Test func applyFailureRollsBackWithoutSaving() {
        let persistence = FailingSyncPersistence(failure: .apply)

        #expect(throws: SyncReconciliationPersistenceError.self) {
            try SyncReconciliationOrchestrator.reconcile(
                using: persistence
            )
        }
        #expect(persistence.didRollback)
        #expect(!persistence.didSave)
    }

    @Test func saveFailureRollsBackAppliedPlan() {
        let persistence = FailingSyncPersistence(failure: .save)

        #expect(throws: SyncReconciliationPersistenceError.self) {
            try SyncReconciliationOrchestrator.reconcile(
                using: persistence
            )
        }
        #expect(persistence.didApply)
        #expect(persistence.didRollback)
    }
}

@MainActor
private final class FailingSyncPersistence: SyncReconciliationPersistence {
    enum Failure {
        case apply
        case save
    }

    let failure: Failure
    var didApply = false
    var didSave = false
    var didRollback = false

    init(failure: Failure) {
        self.failure = failure
    }

    func loadSyncGraph() throws -> SyncGraphSnapshot {
        let id = UUID(
            uuidString: "50000000-0000-0000-0000-000000000001"
        )!
        return SyncGraphSnapshot(
            projects: [],
            recurrenceTemplates: [],
            todos: [
                SyncTodoSnapshot(
                    metadata: SyncRecordMetadata(
                        reference: SyncRecordReference(
                            kind: .todo,
                            localID: "todo"
                        ),
                        semanticID: id,
                        physicalID: nil,
                        createdAt: Date(timeIntervalSince1970: 100),
                        modifiedAt: nil,
                        stableTieBreaker: []
                    ),
                    completedAt: nil,
                    recurrenceSequence: nil,
                    recurrenceTemplateID: nil,
                    projectID: nil
                )
            ]
        )
    }

    func apply(_ mutations: [SyncReconciliationMutation]) throws {
        didApply = true
        if failure == .apply {
            throw SyncReconciliationPersistenceError.applyFailed(
                "Simulated failure"
            )
        }
    }

    func savePreservingMetadata() throws {
        didSave = true
        if failure == .save {
            throw SyncReconciliationPersistenceError.saveFailed(
                "Simulated failure"
            )
        }
    }

    func rollback() {
        didRollback = true
    }
}
