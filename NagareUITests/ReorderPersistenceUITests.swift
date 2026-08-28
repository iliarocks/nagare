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
        XCTAssertFalse(app.buttons["Create Item Type"].exists)
        XCTAssertFalse(app.buttons["Project Picker"].exists)
        XCTAssertTrue(app.buttons["Create Date"].exists)
        XCTAssertFalse(app.buttons["Create Time"].exists)
        XCTAssertTrue(app.buttons["Create Project"].exists)
        XCTAssertTrue(app.buttons["Create Repeat"].exists)
        XCTAssertTrue(app.buttons["Create Submit"].exists)
        XCTAssertFalse(app.buttons["Create Details"].exists)
        XCTAssertFalse(app.buttons["Add Todo"].exists)
        XCTAssertFalse(app.buttons["Cancel"].exists)
        title.typeText("Created With Notes UI")

        let notes = app.textViews["Create Notes"]
        XCTAssertTrue(notes.waitForExistence(timeout: 2))
        notes.tap()
        notes.typeText("Notes entered while creating the todo")

        let submit = app.buttons["Create Submit"]
        XCTAssertTrue(submit.isEnabled)
        submit.tap()
        XCTAssertFalse(title.waitForExistence(timeout: 2))

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
    func testCreateComposerCalendarOpensScheduleEditor() throws {
        let app = XCUIApplication()
        app.launchArguments = [
            "--use-reorder-ui-test-store",
            "--reset-and-seed-reorder-ui-test"
        ]
        app.launch()

        let newItem = app.buttons["New Item"]
        XCTAssertTrue(newItem.waitForExistence(timeout: 5))
        newItem.tap()

        XCTAssertFalse(app.buttons["Create Item Type"].exists)
        let title = app.textFields["Create Title"]
        XCTAssertTrue(title.waitForExistence(timeout: 2))
        title.typeText("Draft Scheduled Todo UI")

        let calendar = app.buttons["Create Date"]
        XCTAssertTrue(calendar.waitForExistence(timeout: 2))
        calendar.tap()

        XCTAssertTrue(app.datePickers["Date"].waitForExistence(timeout: 2))
        XCTAssertFalse(app.switches["Time"].exists)
        XCTAssertTrue(app.staticTexts["No time"].exists)

        let addTime = app.buttons["Add Time"]
        XCTAssertTrue(addTime.exists)
        addTime.tap()
        XCTAssertTrue(app.datePickers["Start Time"].exists)
        XCTAssertTrue(app.buttons["Remove Time"].exists)

        let addEndTime = app.buttons["Add End Time"]
        XCTAssertTrue(addEndTime.exists)
        addEndTime.tap()
        XCTAssertTrue(app.datePickers["End Time"].exists)
        XCTAssertTrue(app.buttons["Remove End Time"].exists)
        XCTAssertFalse(app.buttons["Add End Time"].exists)

        app.buttons["Remove End Time"].tap()
        XCTAssertFalse(app.datePickers["End Time"].exists)
        app.buttons["Remove Time"].tap()
        XCTAssertTrue(app.staticTexts["No time"].exists)
        XCTAssertFalse(app.buttons["Add Todo"].exists)
        XCTAssertFalse(app.buttons["Cancel"].exists)
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
    func testUpcomingRowDragMovesAcrossDateSectionsAndPersists() throws {
        let app = XCUIApplication()
        app.launchArguments = [
            "--use-reorder-ui-test-store",
            "--reset-and-seed-reorder-ui-test"
        ]
        app.launch()

        let upcomingTab = app.buttons["Upcoming"]
        XCTAssertTrue(upcomingTab.waitForExistence(timeout: 5))
        upcomingTab.tap()

        let source = app.buttons["Upcoming Third"]
        let sourceDayPeer = app.buttons["Upcoming Second"]
        let destination = app.buttons["Upcoming Next Day"]
        XCTAssertTrue(source.waitForExistence(timeout: 5))
        XCTAssertTrue(sourceDayPeer.waitForExistence(timeout: 2))
        XCTAssertTrue(destination.waitForExistence(timeout: 2))

        dragRow(source, before: destination)

        XCTAssertTrue(
            source.waitForExistence(timeout: 2),
            "The app must remain alive after a cross-date drag"
        )
        XCTAssertGreaterThan(
            source.frame.minY,
            sourceDayPeer.frame.minY,
            "The dragged row should leave its original date section"
        )
        XCTAssertLessThan(
            abs(source.frame.midY - destination.frame.midY),
            abs(source.frame.midY - sourceDayPeer.frame.midY),
            "The dragged row should join the destination date section"
        )

        app.terminate()

        let relaunchedApp = XCUIApplication()
        relaunchedApp.launchArguments = ["--use-reorder-ui-test-store"]
        relaunchedApp.launch()
        relaunchedApp.buttons["Upcoming"].tap()

        let relaunchedSource = relaunchedApp.buttons["Upcoming Third"]
        let relaunchedPeer = relaunchedApp.buttons["Upcoming Second"]
        let relaunchedDestination = relaunchedApp.buttons[
            "Upcoming Next Day"
        ]
        XCTAssertTrue(relaunchedSource.waitForExistence(timeout: 5))
        XCTAssertTrue(relaunchedPeer.waitForExistence(timeout: 2))
        XCTAssertTrue(relaunchedDestination.waitForExistence(timeout: 2))
        XCTAssertGreaterThan(
            relaunchedSource.frame.minY,
            relaunchedPeer.frame.minY
        )
        XCTAssertLessThan(
            abs(
                relaunchedSource.frame.midY
                    - relaunchedDestination.frame.midY
            ),
            abs(relaunchedSource.frame.midY - relaunchedPeer.frame.midY),
            "The destination date should persist after relaunch"
        )
    }

    @MainActor
    func testTodaySwipeDirectionsExposeDeleteAndDateActions() throws {
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
        XCTAssertFalse(app.buttons["Move Project"].exists)

        editTodo.swipeRight()

        let changeDate = app.buttons["Change Date"]
        XCTAssertTrue(changeDate.waitForExistence(timeout: 2))
        XCTAssertFalse(app.buttons["Move Project"].exists)
        XCTAssertFalse(app.buttons["Delete"].exists)
        changeDate.tap()

        XCTAssertTrue(app.datePickers["Date"].waitForExistence(timeout: 2))
        XCTAssertFalse(app.navigationBars["Edit Details"].exists)
        XCTAssertFalse(app.buttons["Project Picker"].exists)
        XCTAssertFalse(app.buttons["Save Details"].exists)
        XCTAssertFalse(app.buttons["Cancel"].exists)

    }

    @MainActor
    func testCompletedTodoCanBeReinstatedToToday() throws {
        let app = XCUIApplication()
        app.launchArguments = [
            "--use-reorder-ui-test-store",
            "--reset-and-seed-reorder-ui-test"
        ]
        app.launch()

        openCompletedItems(in: app)

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

        openCompletedItems(in: app)

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
    func testTimedTodoSwipeExposesAutosavingScheduleAction() throws {
        let app = XCUIApplication()
        app.launchArguments = [
            "--use-reorder-ui-test-store",
            "--reset-and-seed-reorder-ui-test"
        ]
        app.launch()

        let timedTodo = app.buttons.matching(
            NSPredicate(format: "label BEGINSWITH %@", "Schedule UI")
        ).firstMatch
        XCTAssertTrue(timedTodo.waitForExistence(timeout: 5))
        timedTodo.swipeRight()

        let changeSchedule = app.buttons["Change Date and Time"]
        XCTAssertTrue(changeSchedule.waitForExistence(timeout: 2))
        XCTAssertFalse(app.buttons["Move Project"].exists)
        changeSchedule.tap()

        XCTAssertTrue(
            app.descendants(matching: .any)["Schedule Date Picker"]
                .waitForExistence(timeout: 2)
        )
        XCTAssertFalse(app.switches["Time"].exists)
        XCTAssertTrue(app.datePickers["Start Time"].exists)
        XCTAssertTrue(app.datePickers["End Time"].exists)
        XCTAssertTrue(app.buttons["Remove End Time"].exists)
        XCTAssertFalse(app.navigationBars["Edit Details"].exists)
        XCTAssertFalse(app.buttons["Project Picker"].exists)
        XCTAssertFalse(app.buttons["Save Details"].exists)
        XCTAssertFalse(app.buttons["Cancel"].exists)

        let windowHeight = app.windows.firstMatch.frame.height
        let grabber = app.buttons["Sheet Grabber"]
        XCTAssertTrue(grabber.waitForExistence(timeout: 2))
        XCTAssertGreaterThan(grabber.frame.midY, windowHeight * 0.65)
    }

    @MainActor
    func testLongTimedTodoTitleExpandsToMultipleLines() throws {
        let app = XCUIApplication()
        app.launchArguments = [
            "--use-reorder-ui-test-store",
            "--reset-and-seed-reorder-ui-test"
        ]
        app.launch()

        let timedTodo = app.buttons.matching(
            NSPredicate(format: "label BEGINSWITH %@", "Schedule UI")
        ).firstMatch
        let singleLineTodo = app.buttons["Reorder First"]
        XCTAssertTrue(timedTodo.waitForExistence(timeout: 5))
        XCTAssertTrue(singleLineTodo.waitForExistence(timeout: 5))
        XCTAssertGreaterThan(
            timedTodo.frame.height,
            singleLineTodo.frame.height,
            "A long timed Todo title should expand its row instead of truncating"
        )
    }

    @MainActor
    func testTimedTodoNotesUsesUnifiedScheduleToolbar() throws {
        let app = XCUIApplication()
        app.launchArguments = [
            "--use-reorder-ui-test-store",
            "--reset-and-seed-reorder-ui-test"
        ]
        app.launch()

        let timedTodo = app.buttons.matching(
            NSPredicate(format: "label BEGINSWITH %@", "Schedule UI")
        ).firstMatch
        XCTAssertTrue(timedTodo.waitForExistence(timeout: 5))
        timedTodo.tap()

        let title = app.textFields["Item Title"]
        XCTAssertTrue(title.waitForExistence(timeout: 5))
        let date = app.buttons["Notes Date"]
        let project = app.buttons["Notes Project"]
        let repeatButton = app.buttons["Notes Repeat"]
        XCTAssertTrue(date.waitForExistence(timeout: 2))
        XCTAssertTrue(project.waitForExistence(timeout: 2))
        XCTAssertFalse(repeatButton.exists)
        XCTAssertFalse(app.descendants(matching: .any)["Todo Time"].exists)
        XCTAssertLessThan(
            date.frame.maxY,
            title.frame.minY,
            "The calendar should appear above the title"
        )
        XCTAssertGreaterThan(
            project.frame.minX,
            date.frame.maxX,
            "Project and Repeat should trail the calendar"
        )
        XCTAssertLessThan(abs(project.frame.midY - date.frame.midY), 8)
        project.tap()
        XCTAssertFalse(app.buttons["Edit Details"].exists)
        XCTAssertFalse(app.buttons["Edit Repeat"].exists)
        XCTAssertFalse(app.buttons["Delete Todo"].exists)
        XCTAssertFalse(app.buttons["Delete"].exists)
        XCTAssertFalse(app.buttons["Close"].exists)
        XCTAssertFalse(app.buttons["Item Actions"].exists)
        XCTAssertFalse(app.buttons["Project Picker"].exists)
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
    func testNotesScheduleOpensProgressiveAutosavingEditor() throws {
        let app = XCUIApplication()
        app.launchArguments = [
            "--use-reorder-ui-test-store",
            "--reset-and-seed-reorder-ui-test"
        ]
        app.launch()

        let todo = app.buttons["Reorder First"]
        XCTAssertTrue(todo.waitForExistence(timeout: 5))
        todo.tap()

        let date = app.buttons["Notes Date"]
        let title = app.textFields["Item Title"]
        XCTAssertTrue(date.waitForExistence(timeout: 2))
        XCTAssertTrue(title.waitForExistence(timeout: 2))
        XCTAssertLessThan(date.frame.maxY, title.frame.minY)
        date.tap()

        XCTAssertTrue(app.datePickers["Date"].waitForExistence(timeout: 2))
        XCTAssertFalse(app.switches["Time"].exists)
        XCTAssertTrue(app.staticTexts["No time"].exists)
        XCTAssertTrue(app.buttons["Add Time"].exists)
        XCTAssertFalse(app.navigationBars["Edit Details"].exists)
        XCTAssertFalse(app.buttons["Save Details"].exists)
        XCTAssertFalse(app.buttons["Cancel"].exists)
        XCTAssertFalse(app.buttons["Project Picker"].exists)
    }

    @MainActor
    func testNotesProjectIsInTopToolbarAndOpensProjectMenu() throws {
        let app = XCUIApplication()
        app.launchArguments = [
            "--use-reorder-ui-test-store",
            "--reset-and-seed-reorder-ui-test"
        ]
        app.launch()

        let todo = app.buttons["Recurring Current UI"]
        XCTAssertTrue(todo.waitForExistence(timeout: 5))
        todo.tap()

        let date = app.buttons["Notes Date"]
        let project = app.buttons["Notes Project"]
        XCTAssertTrue(date.waitForExistence(timeout: 2))
        XCTAssertTrue(project.waitForExistence(timeout: 2))
        XCTAssertTrue(project.isHittable)
        let title = app.textFields["Item Title"]
        XCTAssertTrue(title.waitForExistence(timeout: 2))
        XCTAssertLessThan(project.frame.maxY, title.frame.minY)
        XCTAssertGreaterThan(project.frame.minX, date.frame.maxX)
        project.tap()

        XCTAssertTrue(app.buttons["No project"].waitForExistence(timeout: 2))
        XCTAssertTrue(app.buttons["Priority Project UI"].exists)
        XCTAssertTrue(app.buttons["Background Project UI"].exists)
        XCTAssertTrue(app.buttons["Notes Repeat"].exists)
        XCTAssertFalse(app.buttons["Projects"].isSelected)
    }

    @MainActor
    func testTemplateSwipeOpensAutosavingMediumRepeatEditor() throws {
        let app = XCUIApplication()
        app.launchArguments = [
            "--use-reorder-ui-test-store",
            "--reset-and-seed-reorder-ui-test"
        ]
        app.launch()

        app.buttons["Upcoming"].tap()
        let template = app.buttons[
            "Recurring Future UI, future repeating item"
        ].firstMatch
        XCTAssertTrue(template.waitForExistence(timeout: 5))
        template.swipeRight()

        let changeRepeat = app.buttons["Change Repeat"]
        XCTAssertTrue(changeRepeat.waitForExistence(timeout: 2))
        XCTAssertFalse(app.buttons["Move Project"].exists)
        changeRepeat.tap()

        XCTAssertTrue(app.staticTexts["Every"].waitForExistence(timeout: 2))
        XCTAssertFalse(app.navigationBars["Edit Repeat"].exists)
        XCTAssertFalse(app.buttons["Save Repeat"].exists)
        XCTAssertFalse(app.buttons["Cancel"].exists)
        XCTAssertFalse(app.buttons["Project Picker"].exists)

        let windowHeight = app.windows.firstMatch.frame.height
        let grabber = app.buttons["Sheet Grabber"]
        XCTAssertTrue(grabber.waitForExistence(timeout: 2))
        XCTAssertGreaterThan(grabber.frame.midY, windowHeight * 0.35)
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
        XCTAssertFalse(app.buttons["Notes Repeat"].exists)
        XCTAssertFalse(app.buttons["Edit Details"].exists)
        XCTAssertFalse(app.buttons["Delete Todo"].exists)
        XCTAssertFalse(app.buttons["Delete"].exists)
        XCTAssertFalse(app.buttons["Close"].exists)
        XCTAssertFalse(app.buttons["Item Actions"].exists)
        XCTAssertFalse(app.buttons["Project Picker"].exists)
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
        let repeatButton = app.buttons["Notes Repeat"]
        XCTAssertTrue(repeatButton.waitForExistence(timeout: 2))
        XCTAssertFalse(app.buttons["Edit Details"].exists)
        XCTAssertFalse(app.buttons["Delete Todo"].exists)
        XCTAssertFalse(app.buttons["Delete"].exists)
        XCTAssertFalse(app.buttons["Close"].exists)
        XCTAssertFalse(app.buttons["Item Actions"].exists)
        XCTAssertFalse(app.buttons["Add Repeat"].exists)
        XCTAssertFalse(app.buttons["Edit Repeat"].exists)
        XCTAssertFalse(app.buttons["Edit Future Items"].exists)
        XCTAssertFalse(app.buttons["Stop Repeating"].exists)

        repeatButton.tap()
        XCTAssertTrue(app.buttons["Upcoming"].isSelected)
        XCTAssertTrue(
            app.buttons.matching(
                NSPredicate(
                    format: "label CONTAINS %@",
                    "Recurring Future UI"
                )
            ).firstMatch.waitForExistence(timeout: 5)
        )
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

        let date = app.buttons["Notes Date"]
        let project = app.buttons["Notes Project"]
        XCTAssertTrue(date.waitForExistence(timeout: 2))
        XCTAssertTrue(project.waitForExistence(timeout: 2))
        XCTAssertTrue(project.isHittable)
        let repeatButton = app.buttons["Notes Repeat"]
        XCTAssertTrue(repeatButton.waitForExistence(timeout: 2))
        XCTAssertGreaterThan(project.frame.minX, date.frame.maxX)
        XCTAssertLessThan(project.frame.maxY, titleField.frame.minY)

        XCTAssertFalse(app.buttons["Stop Repeating"].exists)
        XCTAssertFalse(app.buttons["Delete"].exists)
        XCTAssertFalse(app.buttons["Edit Repeat"].exists)
        XCTAssertFalse(app.buttons["Close"].exists)
        XCTAssertFalse(app.buttons["Item Actions"].exists)

        repeatButton.tap()
        XCTAssertTrue(app.staticTexts["Every"].waitForExistence(timeout: 2))

    }

    @MainActor
    func testNewProjectStartsAtEndOfBackgroundListAndPersistsNotes() throws {
        let app = XCUIApplication()
        app.launchArguments = [
            "--use-reorder-ui-test-store",
            "--reset-and-seed-reorder-ui-test"
        ]
        app.launch()

        let projectsTab = app.buttons["Projects"]
        XCTAssertTrue(projectsTab.waitForExistence(timeout: 5))
        projectsTab.tap()

        let newProject = app.buttons["New Project"]
        XCTAssertTrue(newProject.waitForExistence(timeout: 2))
        newProject.tap()

        let title = app.textFields["Create Project Title"]
        XCTAssertTrue(title.waitForExistence(timeout: 2))
        title.typeText("Created Background Project UI")

        let notes = app.textViews["Create Project Notes"]
        XCTAssertTrue(notes.waitForExistence(timeout: 2))
        notes.coordinate(
            withNormalizedOffset: CGVector(dx: 0.25, dy: 0.1)
        ).tap()
        notes.typeText("Notes saved with a new background project")
        let submit = app.buttons["Create Project Submit"]
        XCTAssertTrue(submit.waitForExistence(timeout: 2))
        XCTAssertTrue(submit.isEnabled)
        submit.tap()
        XCTAssertFalse(title.waitForExistence(timeout: 2))

        let priority = project(named: "Priority Project UI", in: app)
        let background = project(named: "Background Project UI", in: app)
        let created = project(named: "Created Background Project UI", in: app)
        XCTAssertTrue(priority.waitForExistence(timeout: 5))
        XCTAssertTrue(background.waitForExistence(timeout: 2))
        XCTAssertTrue(created.waitForExistence(timeout: 2))
        XCTAssertGreaterThan(created.frame.minY, background.frame.minY)

        created.tap()
        let savedNotes = app.textViews["Project Notes"]
        XCTAssertTrue(savedNotes.waitForExistence(timeout: 2))
        XCTAssertTrue(
            app.staticTexts["No Project Items"].waitForExistence(timeout: 2)
        )
        XCTAssertEqual(
            savedNotes.value as? String,
            "Notes saved with a new background project"
        )
    }

    @MainActor
    func testProjectCreationCloseDiscardsAndSubmitSaves() throws {
        let app = XCUIApplication()
        app.launchArguments = [
            "--use-reorder-ui-test-store",
            "--reset-and-seed-reorder-ui-test"
        ]
        app.launch()

        let projectsTab = app.buttons["Projects"]
        XCTAssertTrue(projectsTab.waitForExistence(timeout: 5))
        projectsTab.tap()

        let newProject = app.buttons["New Project"]
        XCTAssertTrue(newProject.waitForExistence(timeout: 2))
        newProject.tap()

        let title = app.textFields["Create Project Title"]
        XCTAssertTrue(title.waitForExistence(timeout: 2))
        XCTAssertTrue(app.buttons["Create Project Close"].exists)
        XCTAssertFalse(app.buttons["Create Project Submit"].isEnabled)
        title.typeText("Discarded Project UI")
        app.buttons["Create Project Close"].tap()

        XCTAssertFalse(title.waitForExistence(timeout: 2))
        XCTAssertFalse(project(named: "Discarded Project UI", in: app).exists)

        XCTAssertTrue(newProject.waitForExistence(timeout: 2))
        newProject.tap()

        let replacementTitle = app.textFields["Create Project Title"]
        XCTAssertTrue(replacementTitle.waitForExistence(timeout: 2))
        replacementTitle.typeText("Created After Submit UI")

        let submit = app.buttons["Create Project Submit"]
        XCTAssertTrue(submit.waitForExistence(timeout: 2))
        XCTAssertTrue(submit.isEnabled)
        submit.tap()

        XCTAssertFalse(app.keyboards.firstMatch.exists)
        XCTAssertFalse(replacementTitle.waitForExistence(timeout: 2))

        XCTAssertTrue(
            project(named: "Created After Submit UI", in: app)
                .waitForExistence(timeout: 5)
        )
    }

    @MainActor
    func testProjectDetailShowsCurrentInstanceAndOneRepeatEntry() throws {
        let app = XCUIApplication()
        app.launchArguments = [
            "--use-reorder-ui-test-store",
            "--reset-and-seed-reorder-ui-test"
        ]
        app.launch()

        app.buttons["Projects"].tap()
        let priority = project(named: "Priority Project UI", in: app)
        XCTAssertTrue(priority.waitForExistence(timeout: 5))
        priority.tap()

        XCTAssertTrue(
            app.buttons["Recurring Current UI"].waitForExistence(timeout: 2)
        )
        let repeatEntries = app.buttons.matching(
            identifier: "Recurring Future UI, repeating item"
        )
        let repeatEntry = repeatEntries.firstMatch
        XCTAssertTrue(repeatEntry.waitForExistence(timeout: 2))
        XCTAssertEqual(repeatEntries.count, 1)
    }

    @MainActor
    func testProjectPrioritySwipeActionsPersistDesignation() throws {
        let app = XCUIApplication()
        app.launchArguments = [
            "--use-reorder-ui-test-store",
            "--reset-and-seed-reorder-ui-test"
        ]
        app.launch()

        app.buttons["Projects"].tap()
        let background = project(named: "Background Project UI", in: app)
        XCTAssertTrue(background.waitForExistence(timeout: 5))
        background.swipeRight()
        let prioritize = app.buttons["Prioritize"]
        XCTAssertTrue(prioritize.waitForExistence(timeout: 2))
        XCTAssertTrue(app.buttons["Deprioritize"].exists)
        prioritize.tap()

        app.terminate()

        let relaunchedApp = XCUIApplication()
        relaunchedApp.launchArguments = ["--use-reorder-ui-test-store"]
        relaunchedApp.launch()
        relaunchedApp.buttons["Projects"].tap()

        let relaunchedBackground = project(
            named: "Background Project UI",
            in: relaunchedApp
        )
        XCTAssertTrue(relaunchedBackground.waitForExistence(timeout: 5))
        relaunchedBackground.swipeRight()
        let deprioritize = relaunchedApp.buttons["Deprioritize"]
        XCTAssertTrue(deprioritize.waitForExistence(timeout: 2))
        XCTAssertFalse(relaunchedApp.buttons["Prioritize"].exists)
        deprioritize.tap()

        let secondBackground = project(
            named: "Background Project Second UI",
            in: relaunchedApp
        )
        XCTAssertTrue(secondBackground.waitForExistence(timeout: 2))
        XCTAssertLessThan(
            relaunchedBackground.frame.minY,
            secondBackground.frame.minY,
            "A project returning to Normal should enter at the top of that level"
        )

        relaunchedBackground.swipeRight()
        XCTAssertTrue(
            relaunchedApp.buttons["Prioritize"].waitForExistence(timeout: 2)
        )
        let moveToLow = relaunchedApp.buttons["Deprioritize"]
        XCTAssertTrue(moveToLow.exists)
        moveToLow.tap()

        relaunchedApp.terminate()

        let finalApp = XCUIApplication()
        finalApp.launchArguments = ["--use-reorder-ui-test-store"]
        finalApp.launch()
        finalApp.buttons["Projects"].tap()

        let finalBackground = project(
            named: "Background Project UI",
            in: finalApp
        )
        XCTAssertTrue(finalBackground.waitForExistence(timeout: 5))
        finalBackground.swipeRight()
        XCTAssertTrue(finalApp.buttons["Prioritize"].waitForExistence(timeout: 2))
        XCTAssertFalse(finalApp.buttons["Deprioritize"].exists)
    }

    @MainActor
    func testProjectDragReordersWithinBackgroundListAndPersists() throws {
        let app = XCUIApplication()
        app.launchArguments = [
            "--use-reorder-ui-test-store",
            "--reset-and-seed-reorder-ui-test"
        ]
        app.launch()

        app.buttons["Projects"].tap()
        let first = project(named: "Background Project UI", in: app)
        let second = project(named: "Background Project Second UI", in: app)
        XCTAssertTrue(first.waitForExistence(timeout: 5))
        XCTAssertTrue(second.waitForExistence(timeout: 2))
        XCTAssertLessThan(first.frame.minY, second.frame.minY)

        dragRow(first, after: second)
        XCTAssertLessThan(
            second.frame.minY,
            first.frame.minY,
            "Dragging a project row should reorder its own section"
        )

        app.terminate()

        let relaunchedApp = XCUIApplication()
        relaunchedApp.launchArguments = ["--use-reorder-ui-test-store"]
        relaunchedApp.launch()
        relaunchedApp.buttons["Projects"].tap()

        let relaunchedFirst = project(
            named: "Background Project UI",
            in: relaunchedApp
        )
        let relaunchedSecond = project(
            named: "Background Project Second UI",
            in: relaunchedApp
        )
        XCTAssertTrue(relaunchedFirst.waitForExistence(timeout: 5))
        XCTAssertTrue(relaunchedSecond.waitForExistence(timeout: 2))
        XCTAssertLessThan(
            relaunchedSecond.frame.minY,
            relaunchedFirst.frame.minY
        )
    }

    @MainActor
    func testProjectDragChangesPriorityLevelAndPersists() throws {
        let app = XCUIApplication()
        app.launchArguments = [
            "--use-reorder-ui-test-store",
            "--reset-and-seed-reorder-ui-test"
        ]
        app.launch()

        app.buttons["Projects"].tap()
        let priority = project(named: "Priority Project UI", in: app)
        let background = project(named: "Background Project UI", in: app)
        XCTAssertTrue(priority.waitForExistence(timeout: 5))
        XCTAssertTrue(background.waitForExistence(timeout: 2))

        dragRow(background, before: priority)
        app.terminate()

        let relaunchedApp = XCUIApplication()
        relaunchedApp.launchArguments = ["--use-reorder-ui-test-store"]
        relaunchedApp.launch()
        relaunchedApp.buttons["Projects"].tap()

        let relaunchedPriority = project(
            named: "Priority Project UI",
            in: relaunchedApp
        )
        let relaunchedBackground = project(
            named: "Background Project UI",
            in: relaunchedApp
        )
        XCTAssertTrue(relaunchedPriority.waitForExistence(timeout: 5))
        XCTAssertTrue(relaunchedBackground.waitForExistence(timeout: 2))
        XCTAssertLessThan(
            relaunchedBackground.frame.minY,
            relaunchedPriority.frame.minY
        )
        relaunchedBackground.swipeRight()
        XCTAssertTrue(
            relaunchedApp.buttons["Deprioritize"].waitForExistence(timeout: 2)
        )
        XCTAssertFalse(relaunchedApp.buttons["Prioritize"].exists)
    }

    private func project(
        named title: String,
        in app: XCUIApplication
    ) -> XCUIElement {
        app.descendants(matching: .any)["Project \(title)"]
    }

    @MainActor
    private func openCompletedItems(in app: XCUIApplication) {
        let settings = app.buttons["Settings"]
        XCTAssertTrue(settings.waitForExistence(timeout: 5))
        settings.tap()

        let completedItems = app.buttons["Completed Items"]
        XCTAssertTrue(completedItems.waitForExistence(timeout: 2))
        completedItems.tap()
    }

    @MainActor
    private func dismissCreateComposerSheet(in app: XCUIApplication) {
        let title = app.textFields["Create Title"]
        XCTAssertTrue(title.waitForExistence(timeout: 2))

        let grabber = app.buttons["Sheet Grabber"]
        XCTAssertTrue(grabber.waitForExistence(timeout: 2))
        grabber.coordinate(
            withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5)
        ).press(
            forDuration: 0.1,
            thenDragTo: app.windows.firstMatch.coordinate(
                withNormalizedOffset: CGVector(dx: 0.5, dy: 0.95)
            ),
            withVelocity: .fast,
            thenHoldForDuration: 0
        )

        XCTAssertFalse(title.waitForExistence(timeout: 2))
    }

    @MainActor
    private func dismissSheet(in app: XCUIApplication) {
        let grabber = app.buttons["Sheet Grabber"]
        XCTAssertTrue(grabber.waitForExistence(timeout: 2))
        grabber.swipeDown()
        XCTAssertFalse(grabber.waitForExistence(timeout: 2))
    }

    private func dragRow(
        _ source: XCUIElement,
        after destination: XCUIElement
    ) {
        let sourceCoordinate = source.coordinate(
            withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5)
        )
        let destinationCoordinate = destination.coordinate(
            withNormalizedOffset: CGVector(dx: 0.5, dy: 1.5)
        )

        sourceCoordinate.press(
            forDuration: 1.5,
            thenDragTo: destinationCoordinate,
            withVelocity: .slow,
            thenHoldForDuration: 1
        )
    }

}
