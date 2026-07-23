import XCTest

final class ReorderPersistenceUITests: XCTestCase {
    @MainActor
    func testReorderedTodosKeepTheirPositionsAfterRelaunch() throws {
        let app = XCUIApplication()
        app.launchArguments = [
            "--use-reorder-ui-test-store",
            "--reset-and-seed-reorder-ui-test"
        ]
        app.launch()

        let first = app.buttons["Reorder First"]
        let third = app.buttons["Reorder Third"]
        XCTAssertTrue(first.waitForExistence(timeout: 5))
        XCTAssertTrue(third.waitForExistence(timeout: 5))

        let reorderAction = app.buttons["Test reorder last before first"]
        XCTAssertTrue(reorderAction.waitForExistence(timeout: 2))
        reorderAction.tap()

        app.terminate()

        let relaunchedApp = XCUIApplication()
        relaunchedApp.launchArguments = ["--use-reorder-ui-test-store"]
        relaunchedApp.launch()

        let relaunchedFirst = relaunchedApp.buttons["Reorder First"]
        let relaunchedThird = relaunchedApp.buttons["Reorder Third"]
        XCTAssertTrue(relaunchedFirst.waitForExistence(timeout: 5))
        XCTAssertTrue(relaunchedThird.waitForExistence(timeout: 5))
        XCTAssertLessThan(
            relaunchedThird.frame.minY,
            relaunchedFirst.frame.minY,
            "The persisted order should survive a complete app relaunch"
        )
    }

    @MainActor
    func testUpcomingReorderedTodosKeepTheirPositionsAfterRelaunch() throws {
        let app = XCUIApplication()
        app.launchArguments = [
            "--use-reorder-ui-test-store",
            "--reset-and-seed-reorder-ui-test"
        ]
        app.launch()

        let upcomingTab = app.buttons["Upcoming"]
        XCTAssertTrue(upcomingTab.waitForExistence(timeout: 5))
        upcomingTab.tap()

        let first = app.buttons["Upcoming First"]
        let third = app.buttons["Upcoming Third"]
        XCTAssertTrue(first.waitForExistence(timeout: 5))
        XCTAssertTrue(third.waitForExistence(timeout: 5))

        let reorderAction = app.buttons["Test reorder upcoming last before first"]
        XCTAssertTrue(reorderAction.waitForExistence(timeout: 2))
        reorderAction.tap()

        app.terminate()

        let relaunchedApp = XCUIApplication()
        relaunchedApp.launchArguments = ["--use-reorder-ui-test-store"]
        relaunchedApp.launch()

        let relaunchedUpcomingTab = relaunchedApp.buttons["Upcoming"]
        XCTAssertTrue(relaunchedUpcomingTab.waitForExistence(timeout: 5))
        relaunchedUpcomingTab.tap()

        let relaunchedFirst = relaunchedApp.buttons["Upcoming First"]
        let relaunchedThird = relaunchedApp.buttons["Upcoming Third"]
        XCTAssertTrue(relaunchedFirst.waitForExistence(timeout: 5))
        XCTAssertTrue(relaunchedThird.waitForExistence(timeout: 5))
        XCTAssertLessThan(
            relaunchedThird.frame.minY,
            relaunchedFirst.frame.minY,
            "The Upcoming order should survive a complete app relaunch"
        )
    }

    @MainActor
    func testNotesMenuContainsChangeDateAndDeleteActions() throws {
        let app = XCUIApplication()
        app.launchArguments = [
            "--use-reorder-ui-test-store",
            "--reset-and-seed-reorder-ui-test"
        ]
        app.launch()

        let todo = app.buttons["Reorder First"]
        XCTAssertTrue(todo.waitForExistence(timeout: 5))
        todo.tap()

        let actionsMenu = app.buttons["Item Actions"]
        XCTAssertTrue(actionsMenu.waitForExistence(timeout: 5))
        actionsMenu.tap()

        XCTAssertTrue(app.buttons["Change Date"].waitForExistence(timeout: 2))
        XCTAssertTrue(app.buttons["Delete"].waitForExistence(timeout: 2))
    }

    @MainActor
    func testUpcomingVirtualItemOpensFutureTemplate() throws {
        let app = XCUIApplication()
        app.launchArguments = [
            "--use-reorder-ui-test-store",
            "--reset-and-seed-reorder-ui-test"
        ]
        app.launch()

        let upcomingTab = app.buttons["Upcoming"]
        XCTAssertTrue(upcomingTab.waitForExistence(timeout: 5))
        upcomingTab.tap()

        let virtualItem = app.buttons.matching(
            NSPredicate(
                format: "label CONTAINS %@",
                "Recurring Future UI"
            )
        ).firstMatch
        XCTAssertTrue(
            virtualItem.waitForExistence(timeout: 5),
            "Upcoming should project the future title from the recurrence template"
        )
        virtualItem.tap()

        let titleField = app.textFields["Item Title"]
        XCTAssertTrue(titleField.waitForExistence(timeout: 5))
        XCTAssertEqual(titleField.value as? String, "Recurring Future UI")

        let actionsMenu = app.buttons["Item Actions"]
        XCTAssertTrue(actionsMenu.waitForExistence(timeout: 2))
        actionsMenu.tap()
        XCTAssertTrue(app.buttons["Edit Repeat"].waitForExistence(timeout: 2))
        XCTAssertTrue(app.buttons["Stop Repeating"].waitForExistence(timeout: 2))
    }

}
