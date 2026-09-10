import XCTest

final class AppStoreCaptureTests: XCTestCase {
    @MainActor func testCaptureFourPages() throws {
        continueAfterFailure = false
        let app = XCUIApplication()
        app.launchArguments = ["--use-reorder-ui-test-store", "--capture-app-store", "-ApplePersistenceIgnoreState", "YES"]
        app.launch()
        #if os(macOS)
        let window = app.windows.firstMatch
        XCTAssertTrue(window.waitForExistence(timeout: 20))
        print("CAPTURE_DEFAULT_WINDOW \(window.frame)")
        let corner = window.coordinate(withNormalizedOffset: CGVector(dx: 1, dy: 1)).withOffset(CGVector(dx: -2, dy: -2))
        corner.press(forDuration: 0.15, thenDragTo: window.coordinate(withNormalizedOffset: CGVector(dx: 0.4, dy: 0.4)))
        print("CAPTURE_MINIMUM_WINDOW \(window.frame)")
        #endif
        XCTAssertTrue(app.buttons["Book the train"].waitForExistence(timeout: 15))
        capture(app, "01-today")
        navigate(app, "Upcoming")
        XCTAssertTrue(app.buttons["Choose a place to stay"].waitForExistence(timeout: 10))
        capture(app, "02-upcoming")
        navigate(app, "Projects")
        let project = app.buttons["Project Weekend away"]
        XCTAssertTrue(project.waitForExistence(timeout: 10))
        click(project)
        XCTAssertTrue(app.textFields["Project Title"].waitForExistence(timeout: 10))
        capture(app, "03-project")
        click(app.buttons["Choose a place to stay"])
        XCTAssertTrue(app.textViews["Item Notes"].waitForExistence(timeout: 10))
        capture(app, "04-task-notes")
        app.terminate()
    }

    @MainActor private func navigate(_ app: XCUIApplication, _ name: String) {
        #if os(macOS)
        app.outlines["Sidebar"].cells.containing(.staticText, identifier: name).firstMatch.click()
        #else
        app.buttons[name].tap()
        #endif
    }
    @MainActor private func click(_ element: XCUIElement) {
        #if os(macOS)
        element.click()
        #else
        element.tap()
        #endif
    }
    @MainActor private func capture(_ app: XCUIApplication, _ name: String) {
        #if os(macOS)
        let screenshot = app.windows.firstMatch.screenshot()
        #else
        let screenshot = XCUIScreen.main.screenshot()
        #endif
        let attachment = XCTAttachment(screenshot: screenshot)
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }
}
