import Foundation
import SwiftData
import Testing
@testable import Nagare

@MainActor
struct RecurrenceUIModelTests {
    private var calendar: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        return calendar
    }

    @Test func enablingWeeklyRepeatSelectsMondayFirstAnchorForReferenceDate() throws {
        var state = RecurrenceFormState.disabled

        state.setEnabled(
            true,
            for: .todo,
            referenceDate: date(2026, 7, 8),
            calendar: calendar
        )
        state.selectUnit(
            .week,
            referenceDate: date(2026, 7, 8),
            calendar: calendar
        )

        #expect(state.isEnabled)
        #expect(state.mode == .absolute)
        #expect(state.anchors == [2])
        let optionalRule = try state.rule(
            referenceDate: date(2026, 7, 8),
            calendar: calendar
        )
        let rule = try #require(optionalRule)
        #expect(rule.anchors == [2])
        #expect(rule.reference == date(2026, 7, 6))
    }

    @Test func switchingToMonthlyRepeatUsesZeroBasedDayOfMonth() {
        var state = RecurrenceFormState.enabled(
            for: .todo,
            referenceDate: date(2026, 7, 15),
            calendar: calendar
        )

        state.selectUnit(
            .month,
            referenceDate: date(2026, 7, 15),
            calendar: calendar
        )

        #expect(state.anchors == [14])
        #expect(state.isValid)
    }

    @Test func switchingToYearlyRepeatUsesReferenceDateWithoutAnchors() throws {
        var state = RecurrenceFormState.enabled(
            for: .todo,
            referenceDate: date(2026, 8, 3),
            calendar: calendar
        )

        state.selectUnit(
            .year,
            referenceDate: date(2026, 8, 3),
            calendar: calendar
        )

        #expect(state.anchors.isEmpty)
        #expect(state.isValid)
        let optionalRule = try state.rule(
            referenceDate: date(2026, 8, 3),
            calendar: calendar
        )
        let rule = try #require(optionalRule)
        #expect(rule.unit == .year)
        #expect(rule.reference == date(2026, 8, 3))
    }

    @Test func eventRepeatCannotRemainRelative() {
        var state = RecurrenceFormState.enabled(
            for: .todo,
            referenceDate: date(2026, 7, 1),
            calendar: calendar
        )
        state.selectMode(
            .relative,
            for: .todo,
            referenceDate: date(2026, 7, 1),
            calendar: calendar
        )

        state.prepare(
            for: .event,
            referenceDate: date(2026, 7, 1),
            calendar: calendar
        )

        #expect(state.mode == .absolute)
        #expect(state.isValid)
    }

    @Test func absoluteWeeklyFormRequiresAtLeastOneDay() {
        var state = RecurrenceFormState.enabled(
            for: .todo,
            referenceDate: date(2026, 7, 6),
            calendar: calendar
        )
        state.selectUnit(
            .week,
            referenceDate: date(2026, 7, 6),
            calendar: calendar
        )
        state.toggleAnchor(0)

        #expect(!state.isValid)
        #expect(throws: RecurrenceError.self) {
            _ = try state.rule(
                referenceDate: date(2026, 7, 6),
                calendar: calendar
            )
        }
    }

    @Test func existingFormRoundTripsStoredReferenceAndAnchors() throws {
        let context = try makeContext()
        let todo = insertTodo(
            "Water plants",
            day: date(2026, 7, 8),
            into: context
        )
        let rule = try RecurrenceRule.absolute(
            every: 2,
            unit: .week,
            anchors: [0, 3, 6],
            reference: todo.scheduledDate,
            calendar: calendar
        )
        let template = try RecurrencePersistence.createTemplate(
            for: todo,
            rule: rule,
            in: context
        )

        let state = try RecurrenceFormState.existing(
            template,
            calendar: calendar
        )
        let optionalRule = try state.rule(
            referenceDate: todo.scheduledDate,
            calendar: calendar
        )
        let roundTripped = try #require(optionalRule)

        #expect(roundTripped == rule)
    }

    @Test func disablingRepeatProducesNoRule() throws {
        var state = RecurrenceFormState.enabled(
            for: .todo,
            referenceDate: date(2026, 7, 1),
            calendar: calendar
        )

        state.setEnabled(
            false,
            for: .todo,
            referenceDate: date(2026, 7, 1),
            calendar: calendar
        )

        #expect(state == .disabled)
        #expect(
            try state.rule(
                referenceDate: date(2026, 7, 1),
                calendar: calendar
            ) == nil
        )
    }

    @Test func creationFormRebasesAbsoluteCadenceWhenDateChanges() throws {
        var state = RecurrenceFormState.enabled(
            for: .todo,
            referenceDate: date(2026, 7, 6),
            calendar: calendar
        )
        state.selectUnit(
            .week,
            referenceDate: date(2026, 7, 6),
            calendar: calendar
        )

        state.rebaseReference(
            to: date(2026, 7, 20),
            calendar: calendar
        )

        let optionalRule = try state.rule(
            referenceDate: date(2026, 7, 20),
            calendar: calendar
        )
        let rule = try #require(optionalRule)
        #expect(rule.reference == date(2026, 7, 20))
        #expect(rule.anchors == [0])
    }

    @Test func relativeTodoProjectsExactlyOneFutureInstance() throws {
        let context = try makeContext()
        let todo = insertTodo(
            "Take vitamins",
            day: date(2026, 7, 1),
            into: context
        )
        let rule = try RecurrenceRule.relative(every: 2, unit: .day)
        let template = try RecurrencePersistence.createTemplate(
            for: todo,
            rule: rule,
            in: context
        )

        let items = try VirtualItemProjection.generate(
            from: template,
            starting: date(2026, 7, 2),
            through: date(2027, 1, 1),
            calendar: calendar
        )

        #expect(items.count == 1)
        #expect(items.first?.date == date(2026, 7, 3))
        #expect(items.first?.itemType == .todo)
        #expect(items.first?.startDate == nil)
    }

    @Test func absoluteTodoProjectsEveryInstanceThroughHorizon() throws {
        let context = try makeContext()
        let todo = insertTodo(
            "Practice",
            day: date(2026, 7, 6),
            into: context
        )
        let rule = try RecurrenceRule.absolute(
            every: 1,
            unit: .week,
            anchors: [0, 2],
            reference: todo.scheduledDate,
            calendar: calendar
        )
        let template = try RecurrencePersistence.createTemplate(
            for: todo,
            rule: rule,
            in: context
        )

        let items = try VirtualItemProjection.generate(
            from: template,
            starting: date(2026, 7, 7),
            through: date(2026, 7, 15),
            calendar: calendar
        )

        #expect(items.map(\.date) == [
            date(2026, 7, 8),
            date(2026, 7, 13),
            date(2026, 7, 15)
        ])
        #expect(Set(items.map(\.id)).count == 3)
    }

    @Test func virtualEventCopiesTemplateWallTimes() throws {
        let context = try makeContext()
        let event = Event(
            title: "Office hours",
            scheduledDate: date(2026, 7, 6, hour: 9, minute: 30),
            endDate: date(2026, 7, 6, hour: 11),
            order: "i"
        )
        context.insert(event)
        let rule = try RecurrenceRule.absolute(
            every: 1,
            unit: .week,
            anchors: [0],
            reference: event.scheduledDate,
            calendar: calendar
        )
        let template = try RecurrencePersistence.createTemplate(
            for: event,
            rule: rule,
            in: context,
            calendar: calendar
        )

        let items = try VirtualItemProjection.generate(
            from: template,
            starting: date(2026, 7, 7),
            through: date(2026, 7, 13),
            calendar: calendar
        )
        let item = try #require(items.first)

        #expect(item.startDate == date(2026, 7, 13, hour: 9, minute: 30))
        #expect(item.endDate == date(2026, 7, 13, hour: 11))
        #expect(item.itemType == .event)
    }

    @Test func virtualItemReadsFutureTitleDirectlyFromTemplate() throws {
        let context = try makeContext()
        let todo = insertTodo(
            "Old future title",
            day: date(2026, 7, 1),
            into: context
        )
        let rule = try RecurrenceRule.relative(every: 1, unit: .day)
        let template = try RecurrencePersistence.createTemplate(
            for: todo,
            rule: rule,
            in: context
        )
        let item = try #require(
            VirtualItemProjection.generate(
                from: template,
                starting: date(2026, 7, 2),
                through: date(2026, 7, 2),
                calendar: calendar
            ).first
        )

        template.title = "New future title"

        #expect(item.template.title == "New future title")
        #expect(todo.title == "Old future title")
    }

    @Test func corruptTemplateProjectionFailsWithDiagnosticCode() throws {
        let context = try makeContext()
        let todo = insertTodo(
            "Repeat",
            day: date(2026, 7, 1),
            into: context
        )
        let rule = try RecurrenceRule.relative(every: 1, unit: .day)
        let template = try RecurrencePersistence.createTemplate(
            for: todo,
            rule: rule,
            in: context
        )
        template.currentItemID = UUID()

        do {
            _ = try VirtualItemProjection.generate(
                from: template,
                starting: date(2026, 7, 2),
                through: date(2026, 7, 3),
                calendar: calendar
            )
            Issue.record("Expected virtual projection to fail")
        } catch {
            #expect(error.localizedDescription.contains("VIRTUAL-001"))
        }
    }

    private func makeContext() throws -> ModelContext {
        let configuration = ModelConfiguration(
            for: Todo.self,
            Event.self,
            RecurrenceTemplate.self,
            isStoredInMemoryOnly: true
        )
        let container = try ModelContainer(
            for: Todo.self,
            Event.self,
            RecurrenceTemplate.self,
            configurations: configuration
        )
        return ModelContext(container)
    }

    @discardableResult
    private func insertTodo(
        _ title: String,
        day: Date,
        into context: ModelContext
    ) -> Todo {
        let todo = Todo(
            title: title,
            scheduledDate: day,
            order: "i",
            calendar: calendar
        )
        context.insert(todo)
        return todo
    }

    private func date(
        _ year: Int,
        _ month: Int,
        _ day: Int,
        hour: Int = 0,
        minute: Int = 0
    ) -> Date {
        calendar.date(
            from: DateComponents(
                year: year,
                month: month,
                day: day,
                hour: hour,
                minute: minute
            )
        )!
    }
}
