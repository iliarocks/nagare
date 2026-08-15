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

    @Test func competingTodoSuccessorsHonorReplicatedTemplatePointer() {
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
            .delete(record: competing.metadata.reference)
        ])
    }

    @Test func higherEventSequenceAdvancesStaleTemplateDeterministically() {
        let template = eventTemplate(
            currentItemID: currentID,
            currentSequence: 0
        )
        let old = event(
            id: currentID,
            localID: "old",
            sequence: 0,
            templateID: templateID
        )
        let new = event(
            id: laterID,
            localID: "new",
            sequence: 1,
            templateID: templateID
        )

        let plan = SyncReconciliationPlanner.plan(
            for: graph(templates: [template], events: [old, new])
        )

        #expect(plan.pendingTemplates.isEmpty)
        #expect(plan.mutations == [
            .delete(record: old.metadata.reference),
            .updateTemplate(
                record: template.metadata.reference,
                currentItemID: laterID,
                currentSequence: 1
            )
        ])
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

    private func graph(
        templates: [SyncRecurrenceTemplateSnapshot] = [],
        todos: [SyncTodoSnapshot] = [],
        events: [SyncEventSnapshot] = []
    ) -> SyncGraphSnapshot {
        SyncGraphSnapshot(
            projects: [],
            recurrenceTemplates: templates,
            todos: todos,
            events: events
        )
    }

    private func todoTemplate(
        currentItemID: UUID,
        currentSequence: Int
    ) -> SyncRecurrenceTemplateSnapshot {
        template(
            itemType: "todo",
            currentItemID: currentItemID,
            currentSequence: currentSequence
        )
    }

    private func eventTemplate(
        currentItemID: UUID,
        currentSequence: Int
    ) -> SyncRecurrenceTemplateSnapshot {
        template(
            itemType: "event",
            currentItemID: currentItemID,
            currentSequence: currentSequence
        )
    }

    private func template(
        itemType: String,
        currentItemID: UUID,
        currentSequence: Int
    ) -> SyncRecurrenceTemplateSnapshot {
        SyncRecurrenceTemplateSnapshot(
            metadata: metadata(
                kind: .recurrenceTemplate,
                localID: "template",
                semanticID: templateID
            ),
            itemTypeRawValue: itemType,
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
        templateID: UUID? = nil
    ) -> SyncTodoSnapshot {
        SyncTodoSnapshot(
            metadata: metadata(
                kind: .todo,
                localID: localID,
                semanticID: id,
                physicalID: physicalID ?? id
            ),
            completedAt: completedAt,
            recurrenceSequence: sequence,
            recurrenceTemplateID: templateID,
            projectID: nil
        )
    }

    private func event(
        id: UUID,
        localID: String,
        physicalID: UUID? = nil,
        sequence: Int? = nil,
        templateID: UUID? = nil
    ) -> SyncEventSnapshot {
        SyncEventSnapshot(
            metadata: metadata(
                kind: .event,
                localID: localID,
                semanticID: id,
                physicalID: physicalID
            ),
            recurrenceSequence: sequence,
            recurrenceTemplateID: templateID,
            projectID: nil
        )
    }

    private func metadata(
        kind: SyncEntityKind,
        localID: String,
        semanticID: UUID,
        physicalID: UUID? = nil
    ) -> SyncRecordMetadata {
        SyncRecordMetadata(
            reference: SyncRecordReference(kind: kind, localID: localID),
            semanticID: semanticID,
            physicalID: physicalID ?? semanticID,
            createdAt: timestamp,
            modifiedAt: timestamp,
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
            ],
            events: []
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

    func save(at transactionDate: Date) throws {
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
