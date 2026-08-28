import Foundation
import SwiftData
import Testing
@testable import Nagare

@MainActor
struct DevelopmentSampleDataTests {
    @Test func fixturesPersistUntilExplicitlyRemoved() throws {
        let container = try makeContainer()
        let context = ModelContext(container)
        let date = Date(timeIntervalSince1970: 1_800_000_000)
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!

        let unrelatedProject = Project(
            title: "Keep project",
            order: "a",
            createdAt: date
        )
        let unrelatedTodo = Todo(
            title: "Keep todo",
            scheduledDate: date,
            order: "a"
        )
        let unrelatedTimedTodo = Todo(
            title: "Keep timed todo",
            scheduledDate: date,
            includesTime: true,
            order: "b"
        )
        let unrelatedRule = try RecurrenceRule.relative(every: 1, unit: .day)
        let unrelatedTemplate = RecurrenceTemplate(
            title: "Keep repeat",
            notes: nil,
            rule: unrelatedRule,
            currentItemID: unrelatedTodo.id,
            createdAt: date
        )
        context.insert(unrelatedProject)
        context.insert(unrelatedTodo)
        context.insert(unrelatedTimedTodo)
        context.insert(unrelatedTemplate)
        try context.save()

        try DevelopmentSampleData.seedIfNeeded(
            in: context,
            arguments: ["--seed-development-sample-data"],
            now: date,
            calendar: calendar
        )
        #expect(try context.fetchCount(FetchDescriptor<Project>()) == 4)
        #expect(try context.fetchCount(FetchDescriptor<Todo>()) == 16)
        #expect(try context.fetchCount(FetchDescriptor<Event>()) == 0)
        #expect(
            try context.fetchCount(FetchDescriptor<RecurrenceTemplate>()) == 3
        )

        try DevelopmentSampleData.seedIfNeeded(
            in: context,
            arguments: [],
            now: date,
            calendar: calendar
        )

        #expect(try context.fetchCount(FetchDescriptor<Project>()) == 4)
        #expect(try context.fetchCount(FetchDescriptor<Todo>()) == 16)
        #expect(
            try context.fetchCount(FetchDescriptor<RecurrenceTemplate>()) == 3
        )

        try DevelopmentSampleData.seedIfNeeded(
            in: context,
            arguments: ["--remove-development-sample-data"],
            now: date,
            calendar: calendar
        )

        #expect(try context.fetch(FetchDescriptor<Project>()).map(\.id) == [
            unrelatedProject.id
        ])
        #expect(
            Set(try context.fetch(FetchDescriptor<Todo>()).map(\.id)) == [
                unrelatedTodo.id,
                unrelatedTimedTodo.id
            ]
        )
        #expect(try context.fetch(FetchDescriptor<Event>()).isEmpty)
        #expect(
            try context.fetch(FetchDescriptor<RecurrenceTemplate>()).map(\.id)
                == [unrelatedTemplate.id]
        )
    }

    @Test func replacementKeepsOnlyFreshFixtures() throws {
        let container = try makeContainer()
        let context = ModelContext(container)
        let date = Date(timeIntervalSince1970: 1_800_000_000)
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!

        context.insert(
            Project(title: "Remove project", order: "a", createdAt: date)
        )
        context.insert(
            Todo(title: "Remove todo", scheduledDate: date, order: "a")
        )
        context.insert(
            Event(title: "Remove event", scheduledDate: date, order: "a")
        )
        try context.save()

        try DevelopmentSampleData.seedIfNeeded(
            in: context,
            arguments: ["--replace-with-development-sample-data"],
            now: date,
            calendar: calendar
        )

        #expect(try context.fetchCount(FetchDescriptor<Project>()) == 3)
        #expect(try context.fetchCount(FetchDescriptor<Todo>()) == 14)
        #expect(try context.fetchCount(FetchDescriptor<Event>()) == 0)
        #expect(
            try context.fetchCount(FetchDescriptor<RecurrenceTemplate>()) == 2
        )
        #expect(
            try context.fetch(FetchDescriptor<Project>()).allSatisfy {
                $0.title != "Remove project"
            }
        )
        #expect(
            try context.fetch(FetchDescriptor<Todo>()).allSatisfy {
                $0.title != "Remove todo"
            }
        )
    }

    private func makeContainer() throws -> ModelContainer {
        let configuration = ModelConfiguration(
            schema: NagareSchema.current,
            isStoredInMemoryOnly: true,
            cloudKitDatabase: .none
        )
        return try ModelContainer(
            for: NagareSchema.current,
            configurations: configuration
        )
    }
}
