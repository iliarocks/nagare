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
        XCTAssertFalse(app.buttons["Add Todo"].exists)
        XCTAssertFalse(app.buttons["Cancel"].exists)
        title.typeText("Created With Notes UI")

        let notes = app.textViews["Create Notes"]
        XCTAssertTrue(notes.waitForExistence(timeout: 2))
        notes.tap()
        notes.typeText("Notes entered while creating the todo")

        let details = app.buttons["Create Details"]
        XCTAssertTrue(details.waitForExistence(timeout: 2))
        details.tap()
        XCTAssertFalse(app.navigationBars["Edit Details"].exists)
        XCTAssertTrue(app.buttons["Create Item Type"].exists)
        XCTAssertTrue(app.buttons["Project Picker"].exists)

        dismissSheet(in: app)
        dismissSheet(in: app)

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
    func testCreateComposerSwitchesToEventAndOpensDetails() throws {
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
        title.typeText("Draft Event UI")

        let details = app.buttons["Create Details"]
        XCTAssertTrue(details.waitForExistence(timeout: 2))
        details.tap()

        let typeMenu = app.buttons["Create Item Type"]
        XCTAssertTrue(typeMenu.waitForExistence(timeout: 2))
        typeMenu.tap()

        let event = app.buttons["Event"]
        XCTAssertTrue(event.waitForExistence(timeout: 2))
        event.tap()

        XCTAssertFalse(app.navigationBars["Edit Details"].exists)
        XCTAssertFalse(app.buttons["Add Event"].exists)
        XCTAssertFalse(app.buttons["Cancel"].exists)
        XCTAssertTrue(app.buttons["Project Picker"].exists)
        XCTAssertTrue(app.staticTexts["Time"].exists)

        dismissSheet(in: app)
        dismissSheet(in: app)

        let createdEvent = app.buttons["Draft Event UI"]
        XCTAssertTrue(createdEvent.waitForExistence(timeout: 5))
        createdEvent.tap()
        XCTAssertTrue(
            app.descendants(matching: .any)["Event Time"]
                .waitForExistence(timeout: 2)
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
    func testTodaySwipeDirectionsSeparateDeleteAndEditDetails() throws {
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
        XCTAssertFalse(app.buttons["Edit Details"].exists)

        editTodo.swipeRight()

        let editDetails = app.buttons["Edit Details"]
        XCTAssertTrue(editDetails.waitForExistence(timeout: 2))
        XCTAssertFalse(app.buttons["Delete"].exists)
        editDetails.tap()

        XCTAssertTrue(
            app.navigationBars["Edit Details"].waitForExistence(timeout: 2)
        )
        XCTAssertTrue(app.buttons["Project Picker"].exists)
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
    func testEventDetailsEditorOpensFromSwipeAction() throws {
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

        let editDetails = app.buttons["Edit Details"]
        XCTAssertTrue(editDetails.waitForExistence(timeout: 2))
        editDetails.tap()

        XCTAssertTrue(
            app.navigationBars["Edit Details"].waitForExistence(timeout: 2)
        )
        XCTAssertTrue(app.buttons["Project Picker"].exists)
    }

    @MainActor
    func testTodoProjectCanBeChangedFromEditDetailsAndPersists() throws {
        let app = XCUIApplication()
        app.launchArguments = [
            "--use-reorder-ui-test-store",
            "--reset-and-seed-reorder-ui-test"
        ]
        app.launch()

        let todo = app.buttons["Reorder First"]
        XCTAssertTrue(todo.waitForExistence(timeout: 5))
        todo.swipeRight()

        let editDetails = app.buttons["Edit Details"]
        XCTAssertTrue(editDetails.waitForExistence(timeout: 2))
        editDetails.tap()

        let picker = app.buttons["Project Picker"]
        XCTAssertTrue(picker.waitForExistence(timeout: 2))
        picker.tap()

        let priorityProject = app.buttons["Priority Project UI"]
        XCTAssertTrue(priorityProject.waitForExistence(timeout: 2))
        priorityProject.tap()

        let save = app.buttons["Save Details"]
        XCTAssertTrue(save.waitForExistence(timeout: 2))
        save.tap()

        app.terminate()

        let relaunchedApp = XCUIApplication()
        relaunchedApp.launchArguments = ["--use-reorder-ui-test-store"]
        relaunchedApp.launch()
        relaunchedApp.buttons["Projects"].tap()

        let relaunchedPriorityProject = project(
            named: "Priority Project UI",
            in: relaunchedApp
        )
        XCTAssertTrue(
            relaunchedPriorityProject.waitForExistence(timeout: 5)
        )
        relaunchedPriorityProject.tap()
        XCTAssertTrue(
            relaunchedApp.buttons["Reorder First"]
                .waitForExistence(timeout: 2)
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
        XCTAssertFalse(app.buttons["Edit Details"].exists)
        XCTAssertFalse(app.buttons["Edit Repeat"].exists)
        XCTAssertFalse(app.buttons["Delete Event"].exists)
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
    func testTemplateRepeatProjectCanBeChangedAndPersists() throws {
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
        let picker = app.buttons["Project Picker"]
        XCTAssertTrue(picker.waitForExistence(timeout: 2))
        picker.tap()

        let backgroundProject = app.buttons["Background Project UI"]
        XCTAssertTrue(backgroundProject.waitForExistence(timeout: 2))
        backgroundProject.tap()

        let save = app.buttons["Save Repeat"]
        XCTAssertTrue(save.waitForExistence(timeout: 2))
        save.tap()

        app.terminate()

        let relaunchedApp = XCUIApplication()
        relaunchedApp.launchArguments = ["--use-reorder-ui-test-store"]
        relaunchedApp.launch()
        relaunchedApp.buttons["Projects"].tap()

        let relaunchedBackgroundProject = project(
            named: "Background Project UI",
            in: relaunchedApp
        )
        XCTAssertTrue(
            relaunchedBackgroundProject.waitForExistence(timeout: 5)
        )
        relaunchedBackgroundProject.tap()
        XCTAssertTrue(
            relaunchedApp.buttons["Recurring Current UI"]
                .waitForExistence(timeout: 2)
        )
        XCTAssertTrue(
            relaunchedApp.buttons["Recurring Future UI, repeating item"]
                .waitForExistence(timeout: 2)
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
        XCTAssertFalse(app.buttons["Edit Details"].exists)
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
        title.tap()
        let done = app.keyboards.buttons["Done"]
        XCTAssertTrue(done.waitForExistence(timeout: 2))
        done.tap()
        XCTAssertFalse(app.buttons["Create Project"].exists)
        XCTAssertFalse(app.buttons["Cancel"].exists)
        dismissSheet(in: app)

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
    func testProjectTitleSubmitDismissesKeyboardWhileAutosaving() throws {
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
        title.typeText("Created After Done UI")

        let done = app.keyboards.buttons["Done"]
        XCTAssertTrue(done.waitForExistence(timeout: 2))
        done.tap()

        XCTAssertFalse(app.keyboards.firstMatch.exists)
        XCTAssertTrue(title.exists)
        XCTAssertFalse(app.buttons["Create Project"].exists)
        XCTAssertFalse(app.buttons["Cancel"].exists)

        dismissSheet(in: app)

        XCTAssertTrue(
            project(named: "Created After Done UI", in: app)
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
        deprioritize.tap()

        let secondBackground = project(
            named: "Background Project Second UI",
            in: relaunchedApp
        )
        XCTAssertTrue(secondBackground.waitForExistence(timeout: 2))
        XCTAssertLessThan(
            relaunchedBackground.frame.minY,
            secondBackground.frame.minY,
            "A deprioritized project should enter at the top of the background list"
        )

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
    func testProjectDragCannotChangePriorityDesignation() throws {
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
            relaunchedPriority.frame.minY,
            relaunchedBackground.frame.minY
        )
    }

    private func project(
        named title: String,
        in app: XCUIApplication
    ) -> XCUIElement {
        app.descendants(matching: .any)["Project \(title)"]
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
