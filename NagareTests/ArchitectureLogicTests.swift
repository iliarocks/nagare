import Foundation
import Testing
@testable import Nagare

struct ArchitectureLogicTests {
    @Test func sharedPlannerPreservesMultiSelectionOrder() throws {
        let entries = [
            OrderingPlanner.Entry(id: 1, order: "9"),
            OrderingPlanner.Entry(id: 2, order: "i"),
            OrderingPlanner.Entry(id: 3, order: "r"),
            OrderingPlanner.Entry(id: 4, order: "v")
        ]

        let plan = try OrderingPlanner.move(
            [3, 1],
            before: 2,
            in: entries,
            sourceEntries: [entries[2], entries[0]]
        )

        #expect(plan.orderedIDs == [3, 1, 2, 4])
        #expect(plan.assignments.map(\.id) == [3, 1])
        #expect(plan.assignments[0].order < plan.assignments[1].order)
        #expect(plan.assignments[1].order < entries[1].order)
    }

    @Test func sharedPlannerRepairsInvalidKeysWhenPreparingInsertion() throws {
        let plan = try OrderingPlanner.nextOrder(after: [
            OrderingPlanner.Entry(id: 1, order: "INVALID"),
            OrderingPlanner.Entry(id: 2, order: "i")
        ])

        #expect(plan.repairs.map(\.id) == [1, 2])
        #expect(plan.repairs.allSatisfy {
            FractionalIndex.isValid($0.order)
        })
        #expect(plan.repairs[1].order < plan.order)
    }

    @Test func timedTodoMovementPreservesWallTimeAndDuration() throws {
        let calendar = fixedCalendar
        let start = try #require(calendar.date(
            from: DateComponents(
                year: 2026,
                month: 8,
                day: 1,
                hour: 9,
                minute: 30
            )
        ))
        let destination = try #require(calendar.date(
            from: DateComponents(year: 2026, month: 8, day: 5)
        ))
        let snapshot = ItemSnapshot(
            id: UUID(),
            scheduledDate: start,
            includesTime: true,
            endDate: start.addingTimeInterval(5_400),
            completedAt: nil,
            createdAt: start,
            order: "i",
            projectID: nil,
            projectOrder: nil
        )

        let change = ItemScheduleLogic.moving(
            snapshot,
            to: destination,
            calendar: calendar
        )
        let movedStart = try #require(change.scheduledDate)
        let movedEnd = try #require(change.endDate)

        #expect(calendar.component(.hour, from: movedStart) == 9)
        #expect(calendar.component(.minute, from: movedStart) == 30)
        #expect(movedEnd.timeIntervalSince(movedStart) == 5_400)
    }

    @Test func recurrenceTransitionRejectsSequenceOverflow() throws {
        let calendar = fixedCalendar
        let date = try #require(calendar.date(
            from: DateComponents(year: 2026, month: 8, day: 1)
        ))
        let rule = try RecurrenceRule.relative(every: 1, unit: .day)
        let template = RecurrenceTransitionTemplate(
            title: "Repeat",
            notes: nil,
            rule: rule,
            startTimeSeconds: nil,
            endTimeSeconds: nil,
            currentSequence: .max
        )

        #expect(throws: RecurrenceTransitionLogic.TransitionError.sequenceOverflow) {
            try RecurrenceTransitionLogic.nextTodo(
                after: RecurrenceOccurrenceSnapshot(
                    scheduledDate: date,
                    order: "i",
                    projectOrder: nil
                ),
                from: template,
                createdAt: date,
                calendar: calendar
            )
        }
    }

    @Test func todoMaintenanceProducesOneAtomicChangeSet() throws {
        let calendar = fixedCalendar
        let yesterday = try #require(calendar.date(
            from: DateComponents(year: 2026, month: 8, day: 1)
        ))
        let today = try #require(calendar.date(
            from: DateComponents(year: 2026, month: 8, day: 2)
        ))
        let overdueID = UUID()
        let overdueTimedID = UUID()
        let overdueTimedStart = try #require(calendar.date(
            from: DateComponents(
                year: 2026,
                month: 8,
                day: 1,
                hour: 9,
                minute: 30
            )
        ))
        let plan = try TodoMaintenanceLogic.rollForward(
            [
                ItemSnapshot(
                    id: overdueID,
                    scheduledDate: yesterday,
                    includesTime: false,
                    endDate: nil,
                    completedAt: nil,
                    createdAt: yesterday,
                    order: "9",
                    projectID: nil,
                    projectOrder: nil
                ),
                ItemSnapshot(
                    id: overdueTimedID,
                    scheduledDate: overdueTimedStart,
                    includesTime: true,
                    endDate: overdueTimedStart.addingTimeInterval(5_400),
                    completedAt: nil,
                    createdAt: yesterday,
                    order: "f",
                    projectID: nil,
                    projectOrder: nil
                ),
                ItemSnapshot(
                    id: UUID(),
                    scheduledDate: today,
                    includesTime: true,
                    endDate: nil,
                    completedAt: nil,
                    createdAt: today,
                    order: "i",
                    projectID: nil,
                    projectOrder: nil
                )
            ],
            to: today,
            calendar: calendar
        )

        let change = try #require(
            plan.changes.first(where: { $0.id == overdueID })
        )
        #expect(change.scheduledDate == today)
        #expect(change.order.map(FractionalIndex.isValid) == true)

        let timedChange = try #require(
            plan.changes.first(where: { $0.id == overdueTimedID })
        )
        let timedStart = try #require(timedChange.scheduledDate)
        let timedEnd = try #require(timedChange.endDate)
        #expect(calendar.isDate(timedStart, inSameDayAs: today))
        #expect(calendar.component(.hour, from: timedStart) == 9)
        #expect(calendar.component(.minute, from: timedStart) == 30)
        #expect(timedEnd.timeIntervalSince(timedStart) == 5_400)
    }

    private var fixedCalendar: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        return calendar
    }
}

@MainActor
struct OrderingOrchestratorTests {
    @Test func saveFailureRollsBackThroughPort() throws {
        let calendar = Calendar(identifier: .gregorian)
        let date = try #require(calendar.date(
            from: DateComponents(year: 2026, month: 8, day: 1)
        ))
        let firstID = UUID()
        let secondID = UUID()
        let persistence = FailingItemOrderingPersistence(items: [
            item(firstID, order: "9", date: date),
            item(secondID, order: "i", date: date)
        ])

        #expect(throws: OrderingPersistenceError.self) {
            try ItemOrderingOrchestrator.saveDisplayedOrder(
                [secondID, firstID],
                on: date,
                using: persistence,
                calendar: calendar
            )
        }
        #expect(persistence.didRollback)
    }

    private func item(
        _ id: ItemID,
        order: String,
        date: Date
    ) -> ItemSnapshot {
        ItemSnapshot(
            id: id,
            scheduledDate: date,
            includesTime: false,
            endDate: nil,
            completedAt: nil,
            createdAt: date,
            order: order,
            projectID: nil,
            projectOrder: nil
        )
    }
}

@MainActor
private final class FailingItemOrderingPersistence: ItemOrderingPersistence {
    let items: [ItemSnapshot]
    var didRollback = false

    init(items: [ItemSnapshot]) {
        self.items = items
    }

    func loadItems() throws -> [ItemSnapshot] { items }
    func apply(_ changes: [ItemOrderingChange]) throws {}
    func applyProjectOrder(
        _ changes: [ProjectItemOrderingChange]
    ) throws {}

    func save() throws {
        throw OrderingPersistenceError.saveFailed("Simulated failure")
    }

    func rollback() {
        didRollback = true
    }
}
