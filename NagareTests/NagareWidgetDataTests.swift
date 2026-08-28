import Foundation
import Testing
@testable import Nagare

struct NagareWidgetDataTests {
    private let calendar = Calendar(
        identifier: .gregorian
    )

    @Test
    func topItemUsesNagareOrderAcrossDateOnlyAndTimedTodos() throws {
        let today = try #require(
            calendar.date(
                from: DateComponents(year: 2026, month: 7, day: 27)
            )
        )
        let timedTodoTime = try #require(
            calendar.date(
                from: DateComponents(
                    year: 2026,
                    month: 7,
                    day: 27,
                    hour: 9
                )
            )
        )
        let data = NagareWidgetData(
            items: [
                item(
                    id: "todo",
                    title: "Second",
                    kind: .todo,
                    date: today,
                    order: "m"
                ),
                item(
                    id: "timed-todo",
                    title: "First",
                    kind: .timedTodo,
                    date: timedTodoTime,
                    order: "a"
                )
            ]
        )

        #expect(
            data.topItem(on: today, calendar: calendar)?.title == "First"
        )
    }

    @Test
    func overdueTodoRemainsEligibleForToday() throws {
        let today = try #require(
            calendar.date(
                from: DateComponents(year: 2026, month: 7, day: 27)
            )
        )
        let yesterday = try #require(
            calendar.date(byAdding: .day, value: -1, to: today)
        )
        let data = NagareWidgetData(
            items: [
                item(
                    id: "overdue",
                    title: "Carry me forward",
                    kind: .todo,
                    date: yesterday,
                    order: "a"
                )
            ]
        )

        #expect(
            data.topItem(on: today, calendar: calendar)?.title
                == "Carry me forward"
        )
    }

    @Test
    func pastAndFutureTimedTodosAreNotShownToday() throws {
        let today = try #require(
            calendar.date(
                from: DateComponents(year: 2026, month: 7, day: 27)
            )
        )
        let yesterday = try #require(
            calendar.date(byAdding: .day, value: -1, to: today)
        )
        let tomorrow = try #require(
            calendar.date(byAdding: .day, value: 1, to: today)
        )
        let data = NagareWidgetData(
            items: [
                item(
                    id: "past",
                    title: "Past",
                    kind: .timedTodo,
                    date: yesterday,
                    order: "a"
                ),
                item(
                    id: "future",
                    title: "Future",
                    kind: .timedTodo,
                    date: tomorrow,
                    order: "b"
                )
            ]
        )

        #expect(data.topItem(on: today, calendar: calendar) == nil)
    }

    private func item(
        id: String,
        title: String,
        kind: NagareWidgetItemKind,
        date: Date,
        order: String
    ) -> NagareWidgetItem {
        NagareWidgetItem(
            id: id,
            title: title,
            kind: kind,
            scheduledDate: date,
            endDate: nil,
            order: order
        )
    }
}
