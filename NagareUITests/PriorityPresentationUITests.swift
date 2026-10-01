import XCTest
#if os(macOS)
import AppKit
#endif

final class PriorityPresentationUITests: XCTestCase {
    @MainActor
    func testInheritedPriorityUpdatesInTodayAndUpcoming() async throws {
        let app = launchApp(appearance: "Light")
        let current = app.buttons["Recurring Current UI"]
        XCTAssertTrue(current.waitForExistence(timeout: 5))
        XCTAssertEqual(current.value as? String, "Prioritized project")
        XCTAssertNotEqual(app.buttons["Reorder First"].value as? String, "Prioritized project")
        attach(app, name: "Priority in Today — light")

        navigate("Upcoming", in: app)
        let future = app.buttons["Recurring Future UI, future repeating item"].firstMatch
        XCTAssertTrue(future.waitForExistence(timeout: 5))
        XCTAssertEqual(future.value as? String, "Prioritized project")
        attach(app, name: "Priority in Upcoming — light")

        navigate("Projects", in: app)
        let project = app.buttons["Project Priority Project UI"]
        changePriority(project, action: "Deprioritize", in: app)

        navigate("Today", in: app)
        XCTAssertTrue(current.waitForExistence(timeout: 5))
        XCTAssertNotEqual(current.value as? String, "Prioritized project")
        navigate("Upcoming", in: app)
        XCTAssertTrue(future.waitForExistence(timeout: 5))
        XCTAssertNotEqual(future.value as? String, "Prioritized project")

        navigate("Projects", in: app)
        changePriority(project, action: "Prioritize", in: app)
        navigate("Today", in: app)
        XCTAssertTrue(current.waitForExistence(timeout: 5))
        XCTAssertEqual(current.value as? String, "Prioritized project")

        app.terminate()
        app.launchArguments = ["--use-reorder-ui-test-store"]
        app.launch()
#if os(macOS)
        let productsURL = Bundle.main.bundleURL.deletingLastPathComponent()
        let process = try XCTUnwrap(
            NSRunningApplication.runningApplications(
                withBundleIdentifier: "ilia.page.nagare.dev"
            ).first { $0.bundleURL?.deletingLastPathComponent() == productsURL }
        )
        // Open this test build, even if an installed development copy is running.
        _ = try await NSWorkspace.shared.openApplication(
            at: XCTUnwrap(process.bundleURL),
            configuration: NSWorkspace.OpenConfiguration()
        )
        app.activate()
#endif
        XCTAssertTrue(current.waitForExistence(timeout: 5))
        XCTAssertEqual(current.value as? String, "Prioritized project")
    }

    @MainActor
    func testPriorityAppearanceInDarkMode() throws {
        let app = launchApp(appearance: "Dark")
        let current = app.buttons["Recurring Current UI"]
        XCTAssertTrue(current.waitForExistence(timeout: 5))
        XCTAssertEqual(current.value as? String, "Prioritized project")
        attach(app, name: "Priority in Today — dark")
#if os(macOS)
        XCUIElement.perform(withKeyModifiers: .command) {
            current.click()
            app.buttons["Reorder First"].click()
        }
        XCTAssertEqual(current.value as? String, "Prioritized project, Selected")
        XCTAssertEqual(app.buttons["Reorder First"].value as? String, "Selected")
        attach(app, name: "Priority rows selected — dark")
#endif
        navigate("Upcoming", in: app)
        XCTAssertTrue(app.buttons["Recurring Future UI, future repeating item"].firstMatch.waitForExistence(timeout: 5))
        attach(app, name: "Priority in Upcoming — dark")
    }

    @MainActor
    private func launchApp(appearance: String) -> XCUIApplication {
        continueAfterFailure = false
        let app = XCUIApplication()
        app.launchArguments = [
            "--use-reorder-ui-test-store",
            "--reset-and-seed-reorder-ui-test",
            "-ApplePersistenceIgnoreState", "YES",
            "--ui-test-\(appearance.lowercased())"
        ]
        app.launch()
        return app
    }

    @MainActor
    private func navigate(_ title: String, in app: XCUIApplication) {
#if os(macOS)
        app.outlines["Sidebar"].cells.containing(.staticText, identifier: title).firstMatch.click()
#else
        app.buttons[title].tap()
#endif
    }

    @MainActor
    private func changePriority(_ project: XCUIElement, action: String, in app: XCUIApplication) {
        XCTAssertTrue(project.waitForExistence(timeout: 5))
#if os(macOS)
        project.rightClick()
        XCTAssertTrue(app.menuItems[action].waitForExistence(timeout: 3))
        app.menuItems[action].click()
#else
        project.swipeRight()
        XCTAssertTrue(app.buttons[action].waitForExistence(timeout: 3))
        app.buttons[action].tap()
#endif
    }

    @MainActor
    private func attach(_ app: XCUIApplication, name: String) {
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
