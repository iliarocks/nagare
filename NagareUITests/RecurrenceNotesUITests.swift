import XCTest

final class RecurrenceNotesUITests: XCTestCase {
    @MainActor
    func testRealizedNotesOpenRepeatEditor() throws {
        let app = launchApp()
        let current = app.buttons["Recurring Current UI"]
        XCTAssertTrue(current.waitForExistence(timeout: 5))
        activate(current)

        let title = app.textFields["Item Title"]
        XCTAssertTrue(title.waitForExistence(timeout: 5))
        XCTAssertEqual(title.value as? String, "Recurring Current UI")
        XCTAssertTrue(app.buttons["Notes Date"].isEnabled)

        let repeatButton = app.buttons["Notes Repeat"]
        XCTAssertTrue(repeatButton.waitForExistence(timeout: 5))
        activate(repeatButton)
        XCTAssertTrue(app.staticTexts["Every"].waitForExistence(timeout: 5))
        attachScreenshot(app, name: "Realized item repeat editor")
    }

    @MainActor
    func testVirtualNotesShowOccurrenceDateAndOpenRepeatEditor() throws {
        let app = launchApp()
#if os(macOS)
        let upcoming = app.outlines["Sidebar"].cells.containing(
            .staticText,
            identifier: "Upcoming"
        ).firstMatch
#else
        let upcoming = app.buttons["Upcoming"]
#endif
        XCTAssertTrue(upcoming.waitForExistence(timeout: 5))
        activate(upcoming)

        let virtual = app.buttons.matching(
            NSPredicate(format: "label CONTAINS %@", "Recurring Future UI")
        ).firstMatch
        XCTAssertTrue(virtual.waitForExistence(timeout: 5))
        activate(virtual)

        let title = app.textFields["Item Title"]
        XCTAssertTrue(title.waitForExistence(timeout: 5))
        XCTAssertEqual(title.value as? String, "Recurring Future UI")
        let date = app.buttons["Notes Date"]
        XCTAssertTrue(date.waitForExistence(timeout: 5))
        XCTAssertFalse(date.isEnabled)
        let tomorrow = try XCTUnwrap(
            Calendar.autoupdatingCurrent.date(byAdding: .day, value: 1, to: .now)
        )
        XCTAssertEqual(date.label, tomorrow.formatted(.dateTime.month(.abbreviated).day()))
        attachScreenshot(app, name: "Virtual item occurrence date")

        let repeatButton = app.buttons["Notes Repeat"]
        XCTAssertTrue(repeatButton.waitForExistence(timeout: 5))
        activate(repeatButton)
        XCTAssertTrue(app.staticTexts["Every"].waitForExistence(timeout: 5))
        attachScreenshot(app, name: "Virtual item repeat editor")
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
#if os(macOS)
        app.activate()
#endif
        return app
    }

    @MainActor
    private func activate(_ element: XCUIElement) {
#if os(macOS)
        element.click()
#else
        element.tap()
#endif
    }

    @MainActor
    private func attachScreenshot(_ app: XCUIApplication, name: String) {
#if os(macOS)
        let attachment = XCTAttachment(screenshot: app.windows.firstMatch.screenshot())
#else
        let attachment = XCTAttachment(screenshot: app.screenshot())
#endif
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }
}
