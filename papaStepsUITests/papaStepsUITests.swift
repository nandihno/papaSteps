import XCTest

final class papaStepsUITests: XCTestCase {
    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    @MainActor
    func testLaunchesToWalkTabWithoutPermissionWall() {
        let app = makeApp()
        app.launch()

        XCTAssertTrue(app.navigationBars["Walk"].waitForExistence(timeout: 5))
        XCTAssertFalse(app.alerts.element.exists)
        XCTAssertTrue(app.buttons["walk.start"].exists)

        app.buttons["walk.settings"].tap()
        XCTAssertTrue(app.buttons["walk.diagnostics"].waitForExistence(timeout: 5))
    }

    @MainActor
    func testUndeterminedPermissionsShowContextualPrimer() {
        let app = makeApp(permissionNotDetermined: true)
        app.launch()

        app.buttons["walk.start"].tap()

        XCTAssertTrue(
            app.navigationBars["Prepare Your Walk"].waitForExistence(timeout: 5)
        )
        XCTAssertTrue(app.buttons["walk.permissions.continue"].exists)
        XCTAssertFalse(app.alerts.element.exists)
    }

    @MainActor
    func testOptionalHealthSettingsRequestAccessWithoutBlockingWalks() {
        let app = makeApp()
        app.launch()

        app.buttons["walk.settings"].tap()
        app.buttons["walk.health.settings"].tap()

        XCTAssertTrue(app.navigationBars["Apple Health"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.buttons["health.connect"].exists)

        app.buttons["health.connect"].tap()

        XCTAssertTrue(app.buttons["health.connect"].waitForNonExistence(timeout: 5))
        let requestedExplanation = app.staticTexts.matching(
            NSPredicate(format: "label BEGINSWITH %@", "Access has been requested.")
        ).firstMatch
        XCTAssertTrue(
            requestedExplanation.waitForExistence(timeout: 5)
        )
    }

    @MainActor
    func testManualHealthWorkoutImportAppearsOnceInHistory() {
        let app = makeApp()
        app.launch()

        app.buttons["walk.settings"].tap()
        app.buttons["walk.health.settings"].tap()
        app.buttons["health.import.open"].tap()

        XCTAssertTrue(app.navigationBars["Import Walks"].waitForExistence(timeout: 5))
        let workout = app.descendants(matching: .any).matching(
            NSPredicate(format: "identifier BEGINSWITH 'health.import.workout.'")
        ).firstMatch
        XCTAssertTrue(workout.waitForExistence(timeout: 5))
        workout.tap()
        XCTAssertTrue(app.buttons["health.import.confirm"].isEnabled)
        app.buttons["health.import.confirm"].tap()

        XCTAssertTrue(
            app.staticTexts["Imported 1 walking workout into papaSteps."]
                .waitForExistence(timeout: 5)
        )
        XCTAssertFalse(app.buttons["health.import.confirm"].isEnabled)

        app.tabBars.buttons["History"].tap()
        let historyRow = app.descendants(matching: .any).matching(
            NSPredicate(format: "identifier BEGINSWITH 'history.walk.'")
        ).firstMatch
        XCTAssertTrue(historyRow.waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["Health"].exists)
    }

    @MainActor
    func testProgressTabExplainsEligibilityWhenThereAreNoEligibleWalks() {
        let app = makeApp()
        app.launch()

        app.tabBars.buttons["Progress"].tap()

        XCTAssertTrue(app.navigationBars["Progress"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["No Eligible Walks Yet"].exists)
    }

    @MainActor
    func testManualWalkLifecycleKeepsWalkingThenSavesOneSummary() {
        let app = makeApp()
        app.launch()

        app.buttons["walk.start"].tap()
        XCTAssertTrue(app.buttons["walk.pause"].waitForExistence(timeout: 5))

        app.buttons["walk.pause"].tap()
        XCTAssertTrue(app.buttons["walk.resume"].waitForExistence(timeout: 5))
        app.buttons["walk.resume"].tap()
        XCTAssertTrue(app.buttons["walk.pause"].waitForExistence(timeout: 5))

        app.buttons["walk.done"].tap()
        XCTAssertTrue(
            app.buttons["walk.finish.keepWalking"].waitForExistence(timeout: 5)
        )
        app.buttons["walk.finish.keepWalking"].tap()
        XCTAssertTrue(app.buttons["walk.pause"].waitForExistence(timeout: 5))

        app.buttons["walk.done"].tap()
        XCTAssertTrue(
            app.buttons["walk.finish.confirm"].waitForExistence(timeout: 5)
        )
        app.buttons["walk.finish.confirm"].tap()

        XCTAssertTrue(app.staticTexts["Walk saved"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.buttons["walk.completed.done"].exists)
        XCTAssertTrue(app.descendants(matching: .any)["health.insights"].exists)
        XCTAssertTrue(
            app.staticTexts["Connect Apple Health from the Walk screen settings to add optional post-walk insights."].exists
        )

        app.tabBars.buttons["History"].tap()
        XCTAssertTrue(app.navigationBars["History"].waitForExistence(timeout: 5))
        let historyRow = app.descendants(matching: .any).matching(
            NSPredicate(format: "identifier BEGINSWITH 'history.walk.'")
        ).firstMatch
        XCTAssertTrue(historyRow.waitForExistence(timeout: 5))
        historyRow.tap()
        XCTAssertTrue(
            app.scrollViews["history.walk.detail"].waitForExistence(timeout: 5)
        )
        XCTAssertTrue(app.otherElements["walk.route.map"].exists)
    }

    @MainActor
    func testInterruptedDraftOffersExplicitRecoveryChoices() {
        let app = makeApp(recoverableDraft: true)
        app.launch()

        XCTAssertTrue(app.buttons["walk.recovery.resume"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.buttons["walk.recovery.finish"].exists)
        XCTAssertTrue(app.buttons["walk.recovery.discard"].exists)
        XCTAssertTrue(app.staticTexts["Unfinished walk found"].exists)
    }

    @MainActor
    private func makeApp(
        permissionNotDetermined: Bool = false,
        recoverableDraft: Bool = false
    ) -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments = ["--ui-testing"]
        if permissionNotDetermined {
            app.launchArguments.append("--ui-testing-permissions-not-determined")
        }
        if recoverableDraft {
            app.launchArguments.append("--ui-testing-recovery")
        }
        return app
    }
}
