#if DEBUG
import Foundation
import SwiftData

/// Development-only fixture adapter. Fixtures are opt-in and, once seeded,
/// persist across ordinary launches. They can be removed explicitly by their
/// deterministic IDs without touching unrelated records.
@MainActor
enum DevelopmentSampleData {
    private static let markerProjectID = UUID(
        uuidString: "D3A00000-0000-4000-8000-000000000101"
    )!

    static func seedIfNeeded(
        in context: ModelContext,
        arguments: [String],
        now: Date = .now,
        calendar: Calendar = .autoupdatingCurrent
    ) throws {
        guard !arguments.contains("--use-reorder-ui-test-store") else {
            return
        }

        if arguments.contains("--remove-development-sample-data") {
            try removeLegacySampleData(in: context)
            return
        }

        let replacesExistingData = arguments.contains(
            "--replace-with-development-sample-data"
        )
        guard replacesExistingData
                || arguments.contains("--seed-development-sample-data") else {
            return
        }

        if replacesExistingData {
            try removeAllData(in: context)
        }

        guard try !containsSampleData(in: context) else { return }

        let today = calendar.startOfDay(for: now)
        let tomorrow = try day(1, after: today, calendar: calendar)

        let nagareProject = Project(
            id: markerProjectID,
            title: "Ship Nagare 1.0",
            notes: "Demo project: exercise editing, reordering, notes, completion, and recurring items.",
            isPriority: true,
            order: "i",
            createdAt: try day(-14, after: now, calendar: calendar)
        )
        let kyotoProject = Project(
            id: id("102"),
            title: "Weekend in Kyoto",
            notes: "A small background project with Todos across several days.",
            order: "i",
            createdAt: try day(-6, after: now, calendar: calendar)
        )
        let somedayProject = Project(
            id: id("103"),
            title: "Someday / Maybe",
            notes: "An intentionally sparse project for testing empty and low-density states.",
            order: "r",
            createdAt: try day(-3, after: now, calendar: calendar)
        )

        [nagareProject, kyotoProject, somedayProject].forEach(context.insert)

        insert(
            Todo(
                id: id("201"),
                title: "Review the onboarding flow",
                notes: "Try the happy path, cancel halfway through, and check Dynamic Type at the largest size.",
                scheduledDate: today,
                createdAt: try day(-3, after: now, calendar: calendar),
                order: "9",
                projectOrder: "9",
                calendar: calendar
            ),
            in: nagareProject,
            context: context
        )
        insert(
            Todo(
                id: id("202"),
                title: "Buy oat milk",
                notes: "A simple ungrouped todo for swipe and completion testing.",
                scheduledDate: today,
                order: "i",
                calendar: calendar
            ),
            context: context
        )
        insert(
            Todo(
                id: id("203"),
                title: "Write a thoughtful release note that is long enough to wrap onto a second line",
                notes: "Mention the new Today ordering, project priorities, and recurrence improvements.",
                scheduledDate: today,
                createdAt: try day(-2, after: now, calendar: calendar),
                order: "r",
                projectOrder: "i",
                calendar: calendar
            ),
            in: nagareProject,
            context: context
        )

        insert(
            Todo(
                id: id("301"),
                title: "Design critique",
                notes: "Check spacing, hierarchy, empty states, and destructive-action affordances.",
                scheduledDate: try time(
                    on: today,
                    hour: 10,
                    minute: 30,
                    calendar: calendar
                ),
                includesTime: true,
                endDate: try time(
                    on: today,
                    hour: 11,
                    minute: 15,
                    calendar: calendar
                ),
                createdAt: try day(-4, after: now, calendar: calendar),
                order: "w",
                projectOrder: "r"
            ),
            in: nagareProject,
            context: context
        )
        insert(
            Todo(
                id: id("302"),
                title: "Lunch with Maya",
                notes: "Try rescheduling this timed Todo and editing its end time.",
                scheduledDate: try time(
                    on: today,
                    hour: 12,
                    minute: 30,
                    calendar: calendar
                ),
                includesTime: true,
                endDate: try time(
                    on: today,
                    hour: 13,
                    minute: 30,
                    calendar: calendar
                ),
                order: "z"
            ),
            context: context
        )

        insert(
            Todo(
                id: id("204"),
                title: "Pack a charger and headphones",
                notes: "Move this between days and into or out of the Kyoto project.",
                scheduledDate: tomorrow,
                order: "9",
                projectOrder: "9",
                calendar: calendar
            ),
            in: kyotoProject,
            context: context
        )
        insert(
            Todo(
                id: id("303"),
                title: "Train to Kyoto",
                notes: "Car 8, window seat. This is a multi-hour Todo.",
                scheduledDate: try time(
                    on: tomorrow,
                    hour: 9,
                    minute: 15,
                    calendar: calendar
                ),
                includesTime: true,
                endDate: try time(
                    on: tomorrow,
                    hour: 11,
                    minute: 30,
                    calendar: calendar
                ),
                order: "i",
                projectOrder: "i"
            ),
            in: kyotoProject,
            context: context
        )
        insert(
            Todo(
                id: id("205"),
                title: "Book a tea ceremony",
                notes: "Compare the notes sheet at medium and large detents.",
                scheduledDate: try day(2, after: today, calendar: calendar),
                order: "9",
                projectOrder: "r",
                calendar: calendar
            ),
            in: kyotoProject,
            context: context
        )
        insert(
            Todo(
                id: id("304"),
                title: "Dinner reservation at Gion Karyo",
                notes: "Reservation for two. Test the long-title layout and delete confirmation behavior.",
                scheduledDate: try time(
                    on: try day(4, after: today, calendar: calendar),
                    hour: 19,
                    minute: 0,
                    calendar: calendar
                ),
                includesTime: true,
                endDate: try time(
                    on: try day(4, after: today, calendar: calendar),
                    hour: 21,
                    minute: 0,
                    calendar: calendar
                ),
                order: "9",
                projectOrder: "w"
            ),
            in: kyotoProject,
            context: context
        )
        insert(
            Todo(
                id: id("206"),
                title: "Renew passport",
                notes: "An ungrouped item far enough out to exercise Upcoming scrolling.",
                scheduledDate: try day(9, after: today, calendar: calendar),
                order: "9",
                calendar: calendar
            ),
            context: context
        )

        let dailyTodo = Todo(
            id: id("207"),
            title: "Daily stand-up notes",
            notes: "Complete this to verify that Nagare creates the next recurring occurrence.",
            scheduledDate: today,
            order: "v",
            projectOrder: "v",
            calendar: calendar
        )
        insert(dailyTodo, in: nagareProject, context: context)
        let dailyRule = try RecurrenceRule.relative(every: 1, unit: .day)
        let dailyTemplate = RecurrenceTemplate(
            id: id("401"),
            title: dailyTodo.title,
            notes: dailyTodo.notes,
            rule: dailyRule,
            currentItemID: dailyTodo.id,
            createdAt: now
        )
        context.insert(dailyTemplate)
        dailyTemplate.project = nagareProject
        dailyTodo.recurrenceSequence = 0
        dailyTodo.recurrenceTemplate = dailyTemplate

        let planningDay = try day(3, after: today, calendar: calendar)
        let weeklyTimedTodo = Todo(
            id: id("305"),
            title: "Weekly planning session",
            notes: "Delete one occurrence, then try deleting the entire repeating series.",
            scheduledDate: try time(
                on: planningDay,
                hour: 9,
                minute: 0,
                calendar: calendar
            ),
            includesTime: true,
            endDate: try time(
                on: planningDay,
                hour: 9,
                minute: 45,
                calendar: calendar
            ),
            order: "i",
            projectOrder: "z"
        )
        insert(weeklyTimedTodo, in: nagareProject, context: context)
        let weeklyRule = try RecurrenceRule.absolute(
            every: 7,
            unit: .day,
            reference: planningDay,
            calendar: calendar
        )
        let weeklyTemplate = RecurrenceTemplate(
            id: id("402"),
            title: weeklyTimedTodo.title,
            notes: weeklyTimedTodo.notes,
            rule: weeklyRule,
            startTimeSeconds: 9 * 3_600,
            endTimeSeconds: 9 * 3_600 + 45 * 60,
            currentItemID: weeklyTimedTodo.id,
            createdAt: now
        )
        context.insert(weeklyTemplate)
        weeklyTemplate.project = nagareProject
        weeklyTimedTodo.recurrenceSequence = 0
        weeklyTimedTodo.recurrenceTemplate = weeklyTemplate

        insert(
            Todo(
                id: id("208"),
                title: "Send a test build to the beta group",
                notes: "Completed sample: reinstate it and confirm it returns to Today.",
                scheduledDate: try day(-1, after: today, calendar: calendar),
                completedAt: now.addingTimeInterval(-3_600),
                createdAt: try day(-5, after: now, calendar: calendar),
                order: "z",
                projectOrder: "zz",
                calendar: calendar
            ),
            in: nagareProject,
            context: context
        )
        insert(
            Todo(
                id: id("209"),
                title: "Archive old sketches",
                notes: "A second completed sample in an older date section.",
                scheduledDate: try day(-4, after: today, calendar: calendar),
                completedAt: try time(
                    on: try day(-2, after: today, calendar: calendar),
                    hour: 16,
                    minute: 20,
                    calendar: calendar
                ),
                order: "z",
                calendar: calendar
            ),
            context: context
        )

        try SwiftDataTransaction.save(context)
    }

    private static func removeLegacySampleData(
        in context: ModelContext
    ) throws {
        let projectIDs = Set([markerProjectID, id("102"), id("103")])
        let todoIDs = Set(
            (201...209).map { id(String($0)) }
                + (301...305).map { id(String($0)) }
        )
        let legacyEventIDs = Set((301...305).map { id(String($0)) })
        let templateIDs = Set((401...402).map { id(String($0)) })

        let projects = try context.fetch(FetchDescriptor<Project>()).filter {
            projectIDs.contains($0.id)
        }
        let todos = try context.fetch(FetchDescriptor<Todo>()).filter {
            todoIDs.contains($0.id)
        }
        let events = try context.fetch(FetchDescriptor<Event>()).filter {
            legacyEventIDs.contains($0.id)
        }
        let templates = try context.fetch(
            FetchDescriptor<RecurrenceTemplate>()
        ).filter {
            templateIDs.contains($0.id)
        }

        guard !projects.isEmpty || !todos.isEmpty || !events.isEmpty
                || !templates.isEmpty else {
            return
        }

        templates.forEach(context.delete)
        todos.forEach(context.delete)
        events.forEach(context.delete)
        projects.forEach(context.delete)
        try SwiftDataTransaction.save(context)
    }

    private static func removeAllData(in context: ModelContext) throws {
        let templates = try context.fetch(
            FetchDescriptor<RecurrenceTemplate>()
        )
        let todos = try context.fetch(FetchDescriptor<Todo>())
        let events = try context.fetch(FetchDescriptor<Event>())
        let projects = try context.fetch(FetchDescriptor<Project>())

        templates.forEach(context.delete)
        todos.forEach(context.delete)
        events.forEach(context.delete)
        projects.forEach(context.delete)
        try SwiftDataTransaction.save(context)
    }

    private static func containsSampleData(
        in context: ModelContext
    ) throws -> Bool {
        let markerID = markerProjectID
        var descriptor = FetchDescriptor<Project>(
            predicate: #Predicate { project in
                project.id == markerID
            }
        )
        descriptor.fetchLimit = 1
        return try !context.fetch(descriptor).isEmpty
    }

    private static func insert(
        _ todo: Todo,
        in project: Project? = nil,
        context: ModelContext
    ) {
        context.insert(todo)
        todo.project = project
    }

    private static func id(_ suffix: String) -> UUID {
        UUID(
            uuidString: "D3A00000-0000-4000-8000-000000000\(suffix)"
        )!
    }

    private static func day(
        _ offset: Int,
        after date: Date,
        calendar: Calendar
    ) throws -> Date {
        guard let result = calendar.date(
            byAdding: .day,
            value: offset,
            to: date
        ) else {
            throw DevelopmentSampleDataError.invalidDate
        }
        return result
    }

    private static func time(
        on day: Date,
        hour: Int,
        minute: Int,
        calendar: Calendar
    ) throws -> Date {
        guard let result = calendar.date(
            bySettingHour: hour,
            minute: minute,
            second: 0,
            of: day
        ) else {
            throw DevelopmentSampleDataError.invalidDate
        }
        return result
    }
}

private enum DevelopmentSampleDataError: Error {
    case invalidDate
}
#endif
