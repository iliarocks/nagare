#if os(macOS)
import XCTest

final class DesktopInteractionUITests: XCTestCase {
    @MainActor
    func testProjectCanBeReopenedAfterGoingBack() throws {
        let app = launchApp()
        app.outlines["Sidebar"].cells.containing(.staticText, identifier: "Projects")
            .firstMatch.click()

        let project = app.buttons["Project Priority Project UI"]
        XCTAssertTrue(project.waitForExistence(timeout: 5))
        for _ in 0..<3 {
            XCTAssertTrue(project.wait(for: \.isHittable, toEqual: true, timeout: 5))
            project.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5)).click()
            let title = app.textFields["Project Title"]
            XCTAssertTrue(title.waitForExistence(timeout: 5))
            XCTAssertEqual(title.value as? String, "Priority Project UI")
            app.buttons["Back"].click()
            XCTAssertTrue(project.waitForExistence(timeout: 5))
            XCTAssertNotEqual(project.value as? String, "Selected")
        }
    }

    @MainActor
    func testContextMenuPreservesCommandSelectionAndRowActions() throws {
        let app = launchApp()
        let first = app.buttons["Reorder First"]
        let second = app.buttons["Reorder Second"]
        XCTAssertTrue(first.waitForExistence(timeout: 5))

        XCUIElement.perform(withKeyModifiers: .command) {
            first.click()
            second.click()
        }
        first.rightClick()
        XCTAssertTrue(app.menuItems["Delete 2 Items"].waitForExistence(timeout: 3))
        attachWindow(app, name: "Command-selected rows with context menu")
        app.typeKey(.escape, modifierFlags: [])

        first.rightClick()
        XCTAssertTrue(app.menuItems["Delete 2 Items"].waitForExistence(timeout: 3))
        app.typeKey(.escape, modifierFlags: [])

        let third = app.buttons["Reorder Third"]
        third.rightClick()
        XCTAssertTrue(app.menuItems["Delete"].waitForExistence(timeout: 3))
        attachWindow(app, name: "Temporary context-menu row highlight")
        app.typeKey(.escape, modifierFlags: [])

        // A horizontal trackpad gesture must not expose mobile row actions.
        app.windows.firstMatch.scroll(byDeltaX: -160, deltaY: 0)
        XCTAssertFalse(app.buttons["Delete"].exists)
        app.windows.firstMatch.scroll(byDeltaX: 160, deltaY: 0)
        XCTAssertFalse(app.buttons["Change Date and Time"].exists)
        attachWindow(app, name: "Context-menu highlight dismissed")

        third.rightClick()
        app.menuItems["Change Date and Time"].click()
        XCTAssertTrue(app.datePickers["Schedule Date Picker"].waitForExistence(timeout: 5))
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
        XCTAssertTrue(app.windows.firstMatch.waitForExistence(timeout: 5))
        return app
    }

    @MainActor
    private func attachWindow(_ app: XCUIApplication, name: String) {
        let attachment = XCTAttachment(screenshot: app.windows.firstMatch.screenshot())
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }
}
#endif
