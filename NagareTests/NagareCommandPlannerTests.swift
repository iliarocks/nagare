import Foundation
import Testing
@testable import Nagare

struct NagareCommandPlannerTests {
    private let day = Date(timeIntervalSinceReferenceDate: 800_000_000)
    private let calendar: Calendar = {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        return calendar
    }()

    @Test func editingOnSameDayPreservesItemOrder() throws {
        let id = UUID(uuidString: "00000000-0000-0000-0000-000000000001")!
        let existing = todo(id: id, order: "g")
        let plan = try NagareCommandPlanner.upsertItem(
            itemDraft(title: "Edited", scheduledDate: day),
            existingID: .todo(id),
            in: snapshot(todos: [existing]),
            calendar: calendar
        )

        #expect(plan.order == "g")
        #expect(plan.orderRepairs.isEmpty)
    }

    @Test func movingToAnotherDayPlansANewOrder() throws {
        let existingID = UUID(
            uuidString: "00000000-0000-0000-0000-000000000001"
        )!
        let otherID = UUID(
            uuidString: "00000000-0000-0000-0000-000000000002"
        )!
        let existing = todo(id: existingID, order: "a")
        let other = todo(id: otherID, order: "m")
        let nextDay = day.addingTimeInterval(86_400)

        let plan = try NagareCommandPlanner.upsertItem(
            itemDraft(title: "Moved", scheduledDate: nextDay),
            existingID: .todo(existingID),
            in: snapshot(todos: [existing, other]),
            calendar: calendar
        )

        #expect(FractionalIndex.isValid(plan.order))
        #expect(plan.order > other.order)
    }

    @Test func assigningProjectPlansMembershipOrderAndRepairsLegacyKeys() throws {
        let projectID = UUID(
            uuidString: "00000000-0000-0000-0000-000000000010"
        )!
        let firstID = UUID(
            uuidString: "00000000-0000-0000-0000-000000000001"
        )!
        let secondID = UUID(
            uuidString: "00000000-0000-0000-0000-000000000002"
        )!
        let first = todo(
            id: firstID,
            order: "a",
            projectOrder: nil,
            projectID: projectID
        )
        let second = todo(
            id: secondID,
            order: "b",
            projectOrder: "invalid!",
            projectID: projectID
        )
        let graph = snapshot(
            projects: [project(id: projectID)],
            todos: [second, first]
        )

        let plan = try NagareCommandPlanner.upsertItem(
            itemDraft(
                title: "New project item",
                scheduledDate: day,
                projectID: projectID
            ),
            existingID: nil,
            in: graph,
            calendar: calendar
        )

        #expect(plan.projectOrder.map(FractionalIndex.isValid) == true)
        #expect(plan.projectOrderRepairs.count == 2)
        #expect(plan.projectOrderRepairs.allSatisfy {
            FractionalIndex.isValid($0.projectOrder)
        })
    }

    @Test func repeatedCalendarUIDPreservesItsExistingPosition() throws {
        let event = event(
            id: UUID(
                uuidString: "00000000-0000-0000-0000-000000000003"
            )!,
            order: "q",
            calendarIdentifier: "lunch@example.com"
        )
        let draft = ICalendarEventDraft(
            sourceIdentifier: "lunch@example.com",
            title: "Changed lunch",
            notes: nil,
            scheduledDate: day,
            endDate: nil,
            isAllDay: true
        )

        let plan = try NagareCommandPlanner.upsertCalendarEvent(
            draft,
            in: snapshot(events: [event])
        )

        #expect(plan.order == "q")
        #expect(plan.orderRepairs.isEmpty)
    }

    @Test func planningDoesNotDependOnFetchOrder() throws {
        let first = todo(
            id: UUID(
                uuidString: "00000000-0000-0000-0000-000000000001"
            )!,
            order: "invalid-z"
        )
        let second = todo(
            id: UUID(
                uuidString: "00000000-0000-0000-0000-000000000002"
            )!,
            order: "invalid-a"
        )
        let draft = itemDraft(title: "New", scheduledDate: day)

        let forward = try NagareCommandPlanner.upsertItem(
            draft,
            existingID: nil,
            in: snapshot(todos: [first, second]),
            calendar: calendar
        )
        let reversed = try NagareCommandPlanner.upsertItem(
            draft,
            existingID: nil,
            in: snapshot(todos: [second, first]),
            calendar: calendar
        )

        #expect(forward.order == reversed.order)
        #expect(forward.orderRepairs == reversed.orderRepairs)
    }

    @Test func rejectsMissingEditIdentityWithoutWritingAPartialPlan() {
        #expect(throws: NagareCommandPlanner.PlanningError.missingItem) {
            try NagareCommandPlanner.upsertItem(
                itemDraft(title: "Missing", scheduledDate: day),
                existingID: .todo(UUID()),
                in: .empty,
                calendar: calendar
            )
        }
    }

    @Test func assignmentPlansProjectOrderOutsidePersistence() throws {
        let projectID = UUID(
            uuidString: "00000000-0000-0000-0000-000000000010"
        )!
        let movingID = UUID(
            uuidString: "00000000-0000-0000-0000-000000000001"
        )!
        let destinationID = UUID(
            uuidString: "00000000-0000-0000-0000-000000000002"
        )!
        let graph = snapshot(
            projects: [project(id: projectID)],
            todos: [
                todo(id: movingID, order: "a"),
                todo(
                    id: destinationID,
                    order: "b",
                    projectOrder: "invalid!",
                    projectID: projectID
                )
            ]
        )

        let plan = try NagareCommandPlanner.assign(
            .item(.todo(movingID)),
            to: projectID,
            in: graph
        )

        #expect(plan.itemID == .todo(movingID))
        #expect(plan.projectID == projectID)
        #expect(plan.projectOrder.map(FractionalIndex.isValid) == true)
        #expect(plan.projectOrderRepairs.count == 1)
        #expect(
            plan.projectOrderRepairs.first?.id == .todo(destinationID)
        )
    }

    @Test func reinstatementPlansScheduleAndBothOrderDomains() throws {
        let projectID = UUID(
            uuidString: "00000000-0000-0000-0000-000000000010"
        )!
        let completedID = UUID(
            uuidString: "00000000-0000-0000-0000-000000000001"
        )!
        let activeID = UUID(
            uuidString: "00000000-0000-0000-0000-000000000002"
        )!
        let completed = todo(
            id: completedID,
            order: "a",
            projectOrder: "b",
            projectID: projectID,
            completedAt: day
        )
        let active = todo(
            id: activeID,
            order: "invalid!",
            projectOrder: nil,
            projectID: projectID
        )
        let requestedDate = day.addingTimeInterval(90_000)

        let plan = try NagareCommandPlanner.reinstateTodo(
            completedID,
            on: requestedDate,
            in: snapshot(
                projects: [project(id: projectID)],
                todos: [completed, active]
            ),
            calendar: calendar
        )

        #expect(plan.scheduledDate == calendar.startOfDay(for: requestedDate))
        #expect(FractionalIndex.isValid(plan.order))
        #expect(plan.orderRepairs.count == 2)
        #expect(plan.projectOrder.map(FractionalIndex.isValid) == true)
        #expect(plan.projectOrderRepairs.count == 1)
        #expect(plan.projectOrderRepairs.first?.id == .todo(activeID))
    }

    @Test func transientDuplicateIdentityHasOneDeterministicReadValue() {
        let id = UUID(
            uuidString: "00000000-0000-0000-0000-000000000001"
        )!
        let older = todo(
            id: id,
            syncRecordID: UUID(
                uuidString: "10000000-0000-0000-0000-000000000001"
            )!,
            modifiedAt: day,
            title: "Older",
            order: "a"
        )
        let newer = todo(
            id: id,
            syncRecordID: UUID(
                uuidString: "10000000-0000-0000-0000-000000000002"
            )!,
            modifiedAt: day.addingTimeInterval(1),
            title: "Newer",
            order: "b"
        )
        let graph = snapshot(todos: [newer, older])

        #expect(graph.todosByID[id]?.title == "Newer")
        #expect(graph.canonicalTodos.map(\.title) == ["Newer"])
        #expect(graph.itemsByID[.todo(id)]?.title == "Newer")
    }

    private func snapshot(
        projects: [ProjectRecordSnapshot] = [],
        todos: [TodoRecordSnapshot] = [],
        events: [EventRecordSnapshot] = []
    ) -> NagareDataSnapshot {
        NagareDataSnapshot(
            projects: projects,
            todos: todos,
            events: events,
            recurrenceTemplates: []
        )
    }

    private func itemDraft(
        title: String,
        scheduledDate: Date,
        projectID: UUID? = nil
    ) -> ItemDraft {
        ItemDraft(
            kind: .todo,
            title: title,
            notes: nil,
            scheduledDate: scheduledDate,
            endDate: nil,
            projectID: projectID,
            recurrenceRule: nil,
            eventStartTimeSeconds: nil,
            eventEndTimeSeconds: nil
        )
    }

    private func todo(
        id: UUID,
        syncRecordID: UUID? = nil,
        modifiedAt: Date? = nil,
        title: String = "Todo",
        order: String,
        projectOrder: String? = nil,
        projectID: UUID? = nil,
        completedAt: Date? = nil
    ) -> TodoRecordSnapshot {
        TodoRecordSnapshot(
            id: id,
            syncRecordID: syncRecordID ?? id,
            createdAt: day,
            modifiedAt: modifiedAt,
            title: title,
            notes: nil,
            scheduledDate: day,
            completedAt: completedAt,
            order: order,
            projectOrder: projectOrder,
            recurrenceSequence: nil,
            recurrenceTemplateID: nil,
            projectID: projectID
        )
    }

    private func event(
        id: UUID,
        order: String,
        calendarIdentifier: String?
    ) -> EventRecordSnapshot {
        EventRecordSnapshot(
            id: id,
            syncRecordID: id,
            createdAt: day,
            modifiedAt: nil,
            title: "Event",
            notes: nil,
            scheduledDate: day,
            endDate: nil,
            calendarIdentifier: calendarIdentifier,
            order: order,
            projectOrder: nil,
            recurrenceSequence: nil,
            recurrenceTemplateID: nil,
            projectID: nil
        )
    }

    private func project(id: UUID) -> ProjectRecordSnapshot {
        ProjectRecordSnapshot(
            id: id,
            syncRecordID: id,
            createdAt: day,
            modifiedAt: nil,
            title: "Project",
            notes: nil,
            isPriority: false,
            order: "a"
        )
    }
}
