#if os(macOS)
import AppKit
import XCTest

final class WindowLifecycleUITests: XCTestCase {
    @MainActor
    func testClosingMainWindowQuitsApplication() throws {
        let app = launchApp()

        close(mainWindow(in: app))

        XCTAssertTrue(app.wait(for: .notRunning, timeout: 5))
    }

    @MainActor
    func testClosingMainWindowQuitsWithSettingsAndCompletedOpen() throws {
        let app = launchApp()
        let settings = openSettings(in: app)
        settings.buttons["Completed Items"].click()
        let completed = completedWindow(in: app)
        XCTAssertTrue(completed.waitForExistence(timeout: 5))
        XCTAssertTrue(settings.exists)

        focusMainWindow(in: app)
        close(mainWindow(in: app))

        XCTAssertTrue(app.wait(for: .notRunning, timeout: 5))
        XCTAssertFalse(settings.exists)
        XCTAssertFalse(completed.exists)
    }

    @MainActor
    func testClosingSupportingWindowsKeepsMainWindowRunning() throws {
        let app = launchApp()
        let settings = openSettings(in: app)
        settings.buttons["Completed Items"].click()
        let completed = completedWindow(in: app)
        XCTAssertTrue(completed.waitForExistence(timeout: 5))

        close(completed)
        XCTAssertTrue(completed.waitForNonExistence(timeout: 5))
        XCTAssertTrue(settings.exists)
        XCTAssertTrue(mainWindow(in: app).exists)
        XCTAssertTrue(app.wait(for: .runningForeground, timeout: 5))

        close(settings)
        XCTAssertTrue(settings.waitForNonExistence(timeout: 5))
        XCTAssertTrue(app.wait(for: .runningForeground, timeout: 5))
        focusMainWindow(in: app)
        XCTAssertTrue(app.buttons["Reorder First"].waitForExistence(timeout: 5))
    }

    @MainActor
    func testCommandWOnMainWindowQuitsApplication() throws {
        let app = launchApp()

        focusMainWindow(in: app)
        app.typeKey("w", modifierFlags: .command)

        XCTAssertTrue(app.wait(for: .notRunning, timeout: 5))
    }

    @MainActor
    func testMinimizingMainWindowKeepsApplicationRunning() throws {
        let app = launchApp()
        let main = mainWindow(in: app)
        let minimize = main.buttons[XCUIIdentifierMinimizeWindow]
        XCTAssertTrue(minimize.waitForExistence(timeout: 5))

        minimize.click()

        XCTAssertTrue(main.wait(for: \.isHittable, toEqual: false, timeout: 5))
        XCTAssertNotEqual(app.state, .notRunning)
    }

    @MainActor
    func testProjectTitleAndNotesPersistAfterClosingMainWindow() async throws {
        let app = launchApp()
        let originalProcess = try XCTUnwrap(
            NSRunningApplication.runningApplications(withBundleIdentifier: "ilia.page.nagare.dev").first
        )
        let appURL = try XCTUnwrap(originalProcess.bundleURL)
        openProject(named: "Priority Project UI", in: app)
        let savedTitle = "Project Saved On Close UI"
        let savedNotes = "Project notes retained when the main window closes."

        let title = app.textFields["Project Title"]
        XCTAssertTrue(title.waitForExistence(timeout: 5))
        title.coordinate(withNormalizedOffset: CGVector(dx: 0.1, dy: 0.5)).click()
        title.typeKey("a", modifierFlags: .command)
        title.typeText(savedTitle)

        let notes = app.textViews["Project Notes"]
        XCTAssertTrue(notes.waitForExistence(timeout: 5))
        notes.coordinate(withNormalizedOffset: CGVector(dx: 0.1, dy: 0.2)).click()
        notes.typeKey("a", modifierFlags: .command)
        notes.typeText(savedNotes)
        // Close from the editor without navigating away or adding a save delay.
        close(mainWindow(in: app))
        XCTAssertTrue(app.wait(for: .notRunning, timeout: 5))

        app.launchArguments = ["--use-reorder-ui-test-store"]
        app.launch()
        let relaunchedProcess = try XCTUnwrap(
            NSRunningApplication.runningApplications(withBundleIdentifier: "ilia.page.nagare.dev").first
        )
        XCTAssertNotEqual(originalProcess.processIdentifier, relaunchedProcess.processIdentifier)
        // XCTest launches the process with the isolated store argument. Send
        // the normal Dock/open event to that same process to present its window.
        let reopenedProcess = try await NSWorkspace.shared.openApplication(
            at: appURL,
            configuration: NSWorkspace.OpenConfiguration()
        )
        XCTAssertEqual(reopenedProcess.processIdentifier, relaunchedProcess.processIdentifier)
        app.activate()
        XCTAssertTrue(mainWindow(in: app).waitForExistence(timeout: 5))
        openProject(named: savedTitle, in: app)

        XCTAssertEqual(app.textFields["Project Title"].value as? String, savedTitle)
        let restoredNotes = app.textViews["Project Notes"]
        XCTAssertTrue(restoredNotes.waitForExistence(timeout: 5))
        XCTAssertEqual(restoredNotes.value as? String, savedNotes)
    }

    @MainActor
    private func launchApp() -> XCUIApplication {
        continueAfterFailure = false
        let app = XCUIApplication()
        app.launchArguments = [
            "--use-reorder-ui-test-store",
            "--reset-and-seed-reorder-ui-test",
            "-ApplePersistenceIgnoreState", "YES"
        ]
        app.launch()
        app.activate()
        XCTAssertTrue(mainWindow(in: app).waitForExistence(timeout: 5))
        return app
    }

    @MainActor
    private func mainWindow(in app: XCUIApplication) -> XCUIElement {
        app.windows.containing(.outline, identifier: "Sidebar").firstMatch
    }

    @MainActor
    private func completedWindow(in app: XCUIApplication) -> XCUIElement {
        app.windows["Completed"]
    }

    @MainActor
    private func openSettings(in app: XCUIApplication) -> XCUIElement {
        app.typeKey(",", modifierFlags: .command)
        let settings = app.windows.containing(.button, identifier: "Completed Items").firstMatch
        XCTAssertTrue(settings.waitForExistence(timeout: 5))
        return settings
    }

    @MainActor
    private func focusMainWindow(in app: XCUIApplication) {
        let today = mainWindow(in: app).outlines["Sidebar"].cells
            .containing(.staticText, identifier: "Today").firstMatch
        XCTAssertTrue(today.waitForExistence(timeout: 5))
        today.click()
    }

    @MainActor
    private func close(_ window: XCUIElement) {
        let closeButton = window.buttons[XCUIIdentifierCloseWindow]
        XCTAssertTrue(closeButton.waitForExistence(timeout: 5))
        closeButton.click()
    }

    @MainActor
    private func openProject(named name: String, in app: XCUIApplication) {
        mainWindow(in: app).outlines["Sidebar"].cells
            .containing(.staticText, identifier: "Projects").firstMatch.click()
        let project = app.buttons["Project \(name)"]
        XCTAssertTrue(project.waitForExistence(timeout: 5))
        XCTAssertTrue(project.wait(for: \.isHittable, toEqual: true, timeout: 5))
        project.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5)).click()
        XCTAssertTrue(app.textFields["Project Title"].waitForExistence(timeout: 5))
    }
}
#endif
