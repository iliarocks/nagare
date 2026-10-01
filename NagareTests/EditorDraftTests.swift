import Foundation
import SwiftData
import Testing
@testable import Nagare

@MainActor
struct EditorDraftTests {
    @Test func remoteRefreshMergesUneditedTextFields() {
        var draft = TextEditorDraft(title: "Original", notes: "Old notes")
        draft.notes = "Local notes"
        draft.receive(title: "Remote title", notes: "Old notes")
        #expect(draft.title == "Remote title")
        #expect(draft.notes == "Local notes")
        #expect(draft.changes() == [.notes("Local notes")])

        draft.didSave(draft.changes())
        draft.title = "Local title"
        draft.receive(title: "Remote title", notes: "Remote notes")
        #expect(draft.notes == "Remote notes")
        #expect(draft.changes() == [.title("Local title")])
    }

    @Test func localEditWinsSameFieldConflictWithoutRevertingOtherRemoteFields() throws {
        let fixture = try Fixture()
        var draft = TextEditorDraft(title: "Original", notes: "Old notes")
        draft.title = "Local title"
        let external = ModelContext(fixture.container)
        let todo = try #require(try external.fetch(FetchDescriptor<Todo>()).first)
        todo.title = "Remote title"
        todo.notes = "Remote notes"
        try external.save()
        try fixture.store.reload()
        let remote = try #require(fixture.store.snapshot.todosByID[fixture.todoID])
        draft.receive(title: remote.title, notes: remote.notes)
        #expect(draft.title == "Local title")
        #expect(draft.notes == "Remote notes")
        let changes = draft.changes()
        #expect(changes == [.title("Local title")])
        try fixture.store.updateNote(.todo(fixture.todoID), changes: changes)
        draft.didSave(changes)
        #expect(fixture.store.todos.first?.title == "Local title")
        #expect(fixture.store.todos.first?.notes == "Remote notes")
        #expect(draft.changes().isEmpty)
    }

    @Test func failedTextSaveKeepsDraftAndRetryPreservesRemoteTitle() throws {
        let fixture = try Fixture()
        var draft = TextEditorDraft(title: "Original", notes: "Old notes")
        draft.notes = "Local notes"
        let changes = draft.changes()
        #expect(throws: NagareDataPersistenceError.self) {
            try fixture.store.updateNote(.todo(UUID()), changes: changes)
            draft.didSave(changes)
        }
        #expect(draft.changes() == [.notes("Local notes")])

        let external = ModelContext(fixture.container)
        let externalTodo = try #require(try external.fetch(FetchDescriptor<Todo>()).first)
        externalTodo.title = "Remote title"
        try external.save()
        // The published UI snapshot is deliberately stale during this save.
        #expect(fixture.store.todos.first?.title == "Original")
        try fixture.store.updateNote(.todo(fixture.todoID), changes: draft.changes())
        draft.didSave(changes)
        let saved = try #require(fixture.store.snapshot.todosByID[fixture.todoID])
        draft.receive(title: saved.title, notes: saved.notes)
        #expect(saved.title == "Remote title")
        #expect(saved.notes == "Local notes")
        #expect(draft.title == "Remote title")
        #expect(draft.changes().isEmpty)
    }

    @Test func titlePatchPreservesRemoteNotesAndNotesCanBeCleared() throws {
        let fixture = try Fixture()
        let external = ModelContext(fixture.container)
        let todo = try #require(try external.fetch(FetchDescriptor<Todo>()).first)
        todo.notes = "Remote notes"
        try external.save()

        try fixture.store.updateNote(.todo(fixture.todoID), changes: [.title("Local title")])
        #expect(fixture.store.todos.first?.notes == "Remote notes")
        try fixture.store.updateNote(.todo(fixture.todoID), changes: [.notes(nil)])
        #expect(fixture.store.todos.first?.notes == nil)
        #expect(fixture.store.todos.first?.title == "Local title")
    }

    @Test func blankProjectTitleDoesNotBlockNotesOrOverwriteRemoteTitle() throws {
        let fixture = try Fixture()
        var draft = TextEditorDraft(title: "Project", notes: "Old notes")
        draft.title = "  "
        draft.notes = "Local notes"
        let external = ModelContext(fixture.container)
        let project = try #require(try external.fetch(FetchDescriptor<Project>()).first)
        project.title = "Remote project"
        try external.save()

        let changes = draft.changes(allowsEmptyTitle: false)
        #expect(changes == [.notes("Local notes")])
        try fixture.store.updateProject(fixture.projectID, changes: changes)
        draft.didSave(changes)
        let saved = try #require(fixture.store.snapshot.projectsByID[fixture.projectID])
        #expect(saved.title == "Remote project")
        #expect(saved.notes == "Local notes")
        draft.receive(title: saved.title, notes: saved.notes)
        #expect(draft.changes(allowsEmptyTitle: false).isEmpty)
    }

    @Test func scheduleCanReturnToOpeningDayAndRemoveNewlyAddedTime() throws {
        let fixture = try Fixture()
        let todo = try #require(fixture.store.snapshot.todosByID[fixture.todoID])
        var draft = TodoScheduleDraft(todo: todo, now: fixture.day)
        let save: (TodoScheduleDraft.Schedule) throws -> Void = { schedule in
            try fixture.store.updateTodoSchedule(
                fixture.todoID, scheduledDate: schedule.date,
                includesTime: schedule.includesTime, endDate: schedule.endDate
            )
        }
        draft.scheduledDate = Calendar.current.date(byAdding: .day, value: 1, to: fixture.day)!
        try draft.save(save)
        draft.scheduledDate = fixture.day
        try draft.save(save)
        #expect(fixture.store.todos.first?.scheduledDate == fixture.day)

        draft.includesTime = true
        try draft.save(save)
        #expect(fixture.store.todos.first?.includesTime == true)
        draft.includesTime = false
        try draft.save(save)
        #expect(fixture.store.todos.first?.includesTime == false)
        #expect(fixture.store.todos.first?.endDate == nil)
    }

    @Test func scheduleBaselineAdvancesOnlyAfterSuccessfulSave() throws {
        let fixture = try Fixture()
        let todo = try #require(fixture.store.snapshot.todosByID[fixture.todoID])
        var draft = TodoScheduleDraft(todo: todo)
        let initial = draft.savedSchedule
        draft.includesTime = true
        #expect(throws: SaveFailure.self) {
            try draft.save { _ in throw SaveFailure.unavailable }
        }
        #expect(draft.savedSchedule == initial)
        var saves = 0
        try draft.save { _ in saves += 1 }
        try draft.save { _ in saves += 1 }
        #expect(saves == 1)
        #expect(draft.savedSchedule == draft.schedule)
    }

    @Test func untouchedRepeatEditorDoesNotOverwriteRemoteRule() throws {
        let fixture = try Fixture()
        let template = try #require(fixture.store.snapshot.templatesByID[fixture.templateID])
        var draft = RecurrenceEditorDraft(template: template)
        let external = ModelContext(fixture.container)
        let remote = try #require(try external.fetch(FetchDescriptor<RecurrenceTemplate>()).first)
        remote.interval = 3
        try external.save()

        try draft.save { rule in
            Issue.record("An untouched editor must not write")
            try fixture.store.updateRecurrenceRule(fixture.templateID, rule: rule)
        }
        try fixture.store.reload()
        let updated = try #require(fixture.store.snapshot.templatesByID[fixture.templateID])
        #expect(updated.interval == 3)
        draft.receive(updated)
        #expect(draft.form.interval == 3)
        try draft.save { _ in Issue.record("Refreshing a clean editor must not write") }
    }

    @Test func localRepeatRulePreservesFreshTemplateTimesAndText() throws {
        let fixture = try Fixture()
        let template = try #require(fixture.store.snapshot.templatesByID[fixture.templateID])
        var draft = RecurrenceEditorDraft(template: template)
        draft.form.interval = 2
        let external = ModelContext(fixture.container)
        let remote = try #require(try external.fetch(FetchDescriptor<RecurrenceTemplate>()).first)
        remote.startTimeSeconds = 32_400
        remote.endTimeSeconds = 36_000
        remote.title = "Remote series title"
        remote.notes = "Remote series notes"
        try external.save()

        try draft.save { rule in
            try fixture.store.updateRecurrenceRule(fixture.templateID, rule: rule)
        }
        let saved = try #require(fixture.store.snapshot.templatesByID[fixture.templateID])
        #expect(saved.interval == 2)
        #expect(saved.startTimeSeconds == 32_400)
        #expect(saved.endTimeSeconds == 36_000)
        #expect(saved.title == "Remote series title")
        #expect(saved.notes == "Remote series notes")
        try fixture.store.updateNote(.recurrenceTemplate(fixture.templateID), changes: [.notes("Local series notes")])
        #expect(fixture.store.snapshot.templatesByID[fixture.templateID]?.title == "Remote series title")
    }

    @Test func repeatBaselineAdvancesOnlyAfterSuccessfulSave() throws {
        let fixture = try Fixture()
        let template = try #require(fixture.store.snapshot.templatesByID[fixture.templateID])
        var draft = RecurrenceEditorDraft(template: template)
        draft.form.interval = 2
        #expect(throws: SaveFailure.self) {
            try draft.save { _ in throw SaveFailure.unavailable }
        }
        var intervals: [Int] = []
        try draft.save { intervals.append($0.interval) }
        try draft.save { intervals.append($0.interval) }
        #expect(intervals == [2])
        draft.form.interval = 1
        try draft.save { intervals.append($0.interval) }
        #expect(intervals == [2, 1])
    }

    private enum SaveFailure: Error { case unavailable }

    private struct Fixture {
        let container: ModelContainer
        let store: NagareDataStore
        let todoID: UUID
        let projectID: UUID
        let templateID: UUID
        let day = Calendar.current.startOfDay(for: Date(timeIntervalSinceReferenceDate: 800_000_000))

        init() throws {
            container = try ModelContainer(
                for: NagareSchema.current,
                configurations: ModelConfiguration(isStoredInMemoryOnly: true, cloudKitDatabase: .none)
            )
            let context = ModelContext(container)
            let todo = Todo(title: "Original", notes: "Old notes", scheduledDate: day, order: "a")
            let project = Project(title: "Project", notes: "Old notes", order: "a")
            context.insert(todo)
            context.insert(project)
            let template = try RecurrencePersistence.createTemplate(
                for: todo, rule: .relative(every: 1, unit: .day), in: context
            )
            todoID = todo.id
            projectID = project.id
            templateID = template.id
            let repository = SwiftDataNagareRepository(modelContainer: container)
            store = try NagareDataStore(orchestrator: NagareDataOrchestrator(reader: repository, writer: repository))
        }
    }
}
