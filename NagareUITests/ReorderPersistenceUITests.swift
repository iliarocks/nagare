import XCTest

final class ReorderPersistenceUITests: XCTestCase {
    @MainActor
    func testCreateTodoPersistsNotes() throws {
        let app = XCUIApplication()
        app.launchArguments = [
            "--use-reorder-ui-test-store",
            "--reset-and-seed-reorder-ui-test"
        ]
        app.launch()

        let newItem = app.buttons["New Item"]
        XCTAssertTrue(newItem.waitForExistence(timeout: 5))
        newItem.tap()

        let title = app.textFields["Create Title"]
        XCTAssertTrue(title.waitForExistence(timeout: 2))
        XCTAssertTrue(app.buttons["Todo"].exists)
        XCTAssertTrue(app.buttons["Event"].exists)
        XCTAssertTrue(app.staticTexts["New"].exists)
        title.typeText("Created With Notes UI")

        let notes = app.textFields["Create Notes"]
        XCTAssertTrue(notes.waitForExistence(timeout: 2))
        notes.tap()
        notes.typeText("Notes entered while creating the todo")

        let addTodo = app.buttons["Add Todo"]
        XCTAssertTrue(addTodo.waitForExistence(timeout: 2))
        addTodo.tap()

        let createdTodo = app.buttons["Created With Notes UI"]
        XCTAssertTrue(createdTodo.waitForExistence(timeout: 5))
        createdTodo.tap()

        let savedNotes = app.textViews["Item Notes"]
        XCTAssertTrue(savedNotes.waitForExistence(timeout: 2))
        XCTAssertEqual(
            savedNotes.value as? String,
            "Notes entered while creating the todo"
        )
    }

    @MainActor
    func testStoreOpenFailureShowsRecoveryAlertInsteadOfCrashing() throws {
        let app = XCUIApplication()
        app.launchArguments = ["--simulate-store-open-failure"]
        app.launch()

        let alert = app.alerts["Nagare Couldn't Open Your Items"]
        XCTAssertTrue(
            alert.waitForExistence(timeout: 5),
            "A store-open failure should remain visible and actionable"
        )
        XCTAssertTrue(alert.buttons["OK"].exists)
        XCTAssertTrue(
            alert.staticTexts[
                "Nagare left your data untouched. Close the app and try again. "
                    + "If it still won't open, report error STORE-OPEN-001."
            ].exists
        )

        alert.buttons["OK"].tap()
        XCTAssertTrue(
            app.descendants(matching: .any)["Store Startup Failure"].exists,
            "Dismissing the alert must leave a persistent recovery screen"
        )
    }

    @MainActor
    func testRowDragReordersWithoutUsingAHandle() throws {
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

        dragRow(third, before: first)

        XCTAssertLessThan(
            third.frame.minY,
            first.frame.minY,
            "Dragging the row itself should move it before the first item"
        )

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
            "The order produced by a row drag should persist after relaunch"
        )
    }

    @MainActor
    func testUpcomingRowDragReordersWithinItsSectionWithoutUsingAHandle() throws {
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
        let second = app.buttons["Upcoming Second"]
        let third = app.buttons["Upcoming Third"]
        XCTAssertTrue(first.waitForExistence(timeout: 5))
        XCTAssertTrue(second.waitForExistence(timeout: 5))
        XCTAssertTrue(third.waitForExistence(timeout: 5))

        dragRow(third, before: first)

        XCTAssertLessThan(
            third.frame.minY,
            second.frame.minY,
            "Dragging an Upcoming row should change its position within the date section"
        )

        app.terminate()

        let relaunchedApp = XCUIApplication()
        relaunchedApp.launchArguments = ["--use-reorder-ui-test-store"]
        relaunchedApp.launch()

        let relaunchedUpcomingTab = relaunchedApp.buttons["Upcoming"]
        XCTAssertTrue(relaunchedUpcomingTab.waitForExistence(timeout: 5))
        relaunchedUpcomingTab.tap()

        let relaunchedFirst = relaunchedApp.buttons["Upcoming First"]
        let relaunchedSecond = relaunchedApp.buttons["Upcoming Second"]
        let relaunchedThird = relaunchedApp.buttons["Upcoming Third"]
        XCTAssertTrue(relaunchedFirst.waitForExistence(timeout: 5))
        XCTAssertTrue(relaunchedSecond.waitForExistence(timeout: 5))
        XCTAssertTrue(relaunchedThird.waitForExistence(timeout: 5))
        XCTAssertLessThan(
            relaunchedThird.frame.minY,
            relaunchedSecond.frame.minY,
            "The Upcoming order produced by a row drag should persist"
        )
    }

    @MainActor
    func testTodaySwipeDirectionsSeparateDeleteAndChangeDate() throws {
        let app = XCUIApplication()
        app.launchArguments = [
            "--use-reorder-ui-test-store",
            "--reset-and-seed-reorder-ui-test"
        ]
        app.launch()

        let deleteTodo = app.buttons["Reorder First"]
        let editTodo = app.buttons["Reorder Second"]
        XCTAssertTrue(deleteTodo.waitForExistence(timeout: 5))
        XCTAssertTrue(editTodo.waitForExistence(timeout: 5))
        deleteTodo.swipeLeft()

        XCTAssertTrue(app.buttons["Delete"].waitForExistence(timeout: 2))
        XCTAssertFalse(app.buttons["Change Date"].exists)

        editTodo.swipeRight()

        let changeDate = app.buttons["Change Date"]
        XCTAssertTrue(changeDate.waitForExistence(timeout: 2))
        XCTAssertFalse(app.buttons["Delete"].exists)
        changeDate.tap()

        XCTAssertTrue(
            app.navigationBars["Change Date"].waitForExistence(timeout: 2)
        )
    }

    @MainActor
    func testCompletedTodoCanBeReinstatedToToday() throws {
        let app = XCUIApplication()
        app.launchArguments = [
            "--use-reorder-ui-test-store",
            "--reset-and-seed-reorder-ui-test"
        ]
        app.launch()

        let completedButton = app.buttons["Completed"]
        XCTAssertTrue(completedButton.waitForExistence(timeout: 5))
        completedButton.tap()

        let completedTodo = app.buttons["Completed Todo UI, completed"]
        XCTAssertTrue(completedTodo.waitForExistence(timeout: 2))
        completedTodo.swipeRight()

        let reinstate = app.buttons["Reinstate"]
        XCTAssertTrue(reinstate.waitForExistence(timeout: 2))
        reinstate.tap()
        XCTAssertFalse(completedTodo.waitForExistence(timeout: 1))

        XCTAssertFalse(app.buttons["Close Completed"].exists)
        app.swipeDown()

        XCTAssertTrue(
            app.buttons["Completed Todo UI"].waitForExistence(timeout: 2),
            "Reinstating a future Todo should make it immediately visible in Today"
        )
    }

    @MainActor
    func testCompletedTodoCanBePermanentlyDeleted() throws {
        let app = XCUIApplication()
        app.launchArguments = [
            "--use-reorder-ui-test-store",
            "--reset-and-seed-reorder-ui-test"
        ]
        app.launch()

        let completedButton = app.buttons["Completed"]
        XCTAssertTrue(completedButton.waitForExistence(timeout: 5))
        completedButton.tap()

        let completedTodo = app.buttons["Completed Todo UI, completed"]
        XCTAssertTrue(completedTodo.waitForExistence(timeout: 2))
        completedTodo.swipeLeft()

        let delete = app.buttons["Delete"]
        XCTAssertTrue(delete.waitForExistence(timeout: 2))
        delete.tap()

        XCTAssertFalse(completedTodo.waitForExistence(timeout: 1))
        XCTAssertTrue(
            app.staticTexts["No Completed Todos"].waitForExistence(timeout: 2)
        )
    }

    @MainActor
    func testEventScheduleEditorOpensFromSwipeAction() throws {
        let app = XCUIApplication()
        app.launchArguments = [
            "--use-reorder-ui-test-store",
            "--reset-and-seed-reorder-ui-test"
        ]
        app.launch()

        let event = app.buttons.matching(
            NSPredicate(format: "label BEGINSWITH %@", "Schedule UI")
        ).firstMatch
        XCTAssertTrue(event.waitForExistence(timeout: 5))
        event.swipeRight()

        let changeSchedule = app.buttons["Change Schedule"]
        XCTAssertTrue(changeSchedule.waitForExistence(timeout: 2))
        changeSchedule.tap()

        XCTAssertTrue(
            app.navigationBars["Change Schedule"].waitForExistence(timeout: 2)
        )
    }

    @MainActor
    func testLongEventTitleExpandsToMultipleLines() throws {
        let app = XCUIApplication()
        app.launchArguments = [
            "--use-reorder-ui-test-store",
            "--reset-and-seed-reorder-ui-test"
        ]
        app.launch()

        let event = app.buttons.matching(
            NSPredicate(format: "label BEGINSWITH %@", "Schedule UI")
        ).firstMatch
        let singleLineTodo = app.buttons["Reorder First"]
        XCTAssertTrue(event.waitForExistence(timeout: 5))
        XCTAssertTrue(singleLineTodo.waitForExistence(timeout: 5))
        XCTAssertGreaterThan(
            event.frame.height,
            singleLineTodo.frame.height,
            "A long event title should expand its row instead of truncating"
        )
    }

    @MainActor
    func testEventNotesShowsTimeInlineWithoutScheduleAction() throws {
        let app = XCUIApplication()
        app.launchArguments = [
            "--use-reorder-ui-test-store",
            "--reset-and-seed-reorder-ui-test"
        ]
        app.launch()

        let event = app.buttons.matching(
            NSPredicate(format: "label BEGINSWITH %@", "Schedule UI")
        ).firstMatch
        XCTAssertTrue(event.waitForExistence(timeout: 5))
        event.tap()

        let title = app.textFields["Item Title"]
        let time = app.descendants(matching: .any)["Event Time"]
        XCTAssertTrue(title.waitForExistence(timeout: 5))
        XCTAssertTrue(time.waitForExistence(timeout: 2))
        XCTAssertGreaterThan(
            time.frame.minX,
            title.frame.minX,
            "The event time should trail the title"
        )
        XCTAssertLessThan(time.frame.minY, title.frame.maxY)
        XCTAssertGreaterThan(time.frame.maxY, title.frame.minY)
        XCTAssertFalse(app.buttons["Change Date"].exists)
        XCTAssertFalse(app.buttons["Change Schedule"].exists)
        XCTAssertFalse(app.buttons["Edit Repeat"].exists)
        XCTAssertFalse(app.buttons["Delete Event"].exists)
        XCTAssertFalse(app.buttons["Delete"].exists)
        XCTAssertFalse(app.buttons["Close"].exists)
        XCTAssertFalse(app.buttons["Item Actions"].exists)
    }

    @MainActor
    func testNotesOpenInMediumSheet() throws {
        let app = XCUIApplication()
        app.launchArguments = [
            "--use-reorder-ui-test-store",
            "--reset-and-seed-reorder-ui-test"
        ]
        app.launch()

        let todo = app.buttons["Reorder First"]
        XCTAssertTrue(todo.waitForExistence(timeout: 5))
        todo.tap()

        let title = app.textFields["Item Title"]
        XCTAssertTrue(title.waitForExistence(timeout: 5))
        let windowHeight = app.windows.firstMatch.frame.height
        XCTAssertGreaterThan(title.frame.midY, windowHeight * 0.4)
        XCTAssertLessThan(title.frame.midY, windowHeight * 0.7)
    }

    @MainActor
    func testTemplateSwipeRightOpensChangeRepeat() throws {
        let app = XCUIApplication()
        app.launchArguments = [
            "--use-reorder-ui-test-store",
            "--reset-and-seed-reorder-ui-test"
        ]
        app.launch()

        let upcomingTab = app.buttons["Upcoming"]
        XCTAssertTrue(upcomingTab.waitForExistence(timeout: 5))
        upcomingTab.tap()

        let template = app.buttons[
            "Recurring Future UI, future repeating item"
        ].firstMatch
        XCTAssertTrue(template.waitForExistence(timeout: 5))
        template.swipeRight()

        let changeRepeat = app.buttons["Change Repeat"]
        XCTAssertTrue(changeRepeat.waitForExistence(timeout: 2))
        XCTAssertFalse(app.buttons["Delete"].exists)
        changeRepeat.tap()

        XCTAssertTrue(
            app.navigationBars["Edit Repeat"].waitForExistence(timeout: 2)
        )
    }

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

    private func dragRow(
        _ source: XCUIElement,
        before destination: XCUIElement
    ) {
        let sourceCoordinate = source.coordinate(
            withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5)
        )
        let destinationCoordinate = destination.coordinate(
            withNormalizedOffset: CGVector(dx: 0.5, dy: 0.05)
        )

        sourceCoordinate.press(
            forDuration: 1.5,
            thenDragTo: destinationCoordinate,
            withVelocity: .slow,
            thenHoldForDuration: 1
        )
    }

    @MainActor
    func testTodoNotesHasNoInlineManagementActions() throws {
        let app = XCUIApplication()
        app.launchArguments = [
            "--use-reorder-ui-test-store",
            "--reset-and-seed-reorder-ui-test"
        ]
        app.launch()

        let todo = app.buttons["Reorder First"]
        XCTAssertTrue(todo.waitForExistence(timeout: 5))
        todo.tap()

        XCTAssertTrue(app.textFields["Item Title"].waitForExistence(timeout: 2))
        XCTAssertFalse(app.buttons["Change Date"].exists)
        XCTAssertFalse(app.buttons["Change Schedule"].exists)
        XCTAssertFalse(app.buttons["Delete Todo"].exists)
        XCTAssertFalse(app.buttons["Delete"].exists)
        XCTAssertFalse(app.buttons["Close"].exists)
        XCTAssertFalse(app.buttons["Item Actions"].exists)
        XCTAssertFalse(app.buttons["Add Repeat"].exists)
        XCTAssertFalse(app.buttons["Edit Repeat"].exists)
        XCTAssertFalse(app.buttons["Edit Future Items"].exists)
        XCTAssertFalse(app.buttons["Stop Repeating"].exists)
    }

    @MainActor
    func testCurrentRecurrenceInstanceDoesNotExposeTemplateControls() throws {
        let app = XCUIApplication()
        app.launchArguments = [
            "--use-reorder-ui-test-store",
            "--reset-and-seed-reorder-ui-test"
        ]
        app.launch()

        let currentInstance = app.buttons["Recurring Current UI"]
        XCTAssertTrue(currentInstance.waitForExistence(timeout: 5))
        currentInstance.tap()

        XCTAssertTrue(app.textFields["Item Title"].waitForExistence(timeout: 2))
        XCTAssertFalse(app.buttons["Change Date"].exists)
        XCTAssertFalse(app.buttons["Delete Todo"].exists)
        XCTAssertFalse(app.buttons["Delete"].exists)
        XCTAssertFalse(app.buttons["Close"].exists)
        XCTAssertFalse(app.buttons["Item Actions"].exists)
        XCTAssertFalse(app.buttons["Add Repeat"].exists)
        XCTAssertFalse(app.buttons["Edit Repeat"].exists)
        XCTAssertFalse(app.buttons["Edit Future Items"].exists)
        XCTAssertFalse(app.buttons["Stop Repeating"].exists)
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

        XCTAssertFalse(app.buttons["Stop Repeating"].exists)
        XCTAssertFalse(app.buttons["Delete"].exists)
        XCTAssertFalse(app.buttons["Edit Repeat"].exists)
        XCTAssertFalse(app.buttons["Close"].exists)
        XCTAssertFalse(app.buttons["Item Actions"].exists)

    }

}
