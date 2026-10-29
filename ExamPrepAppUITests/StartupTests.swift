import XCTest

@MainActor final class StartupTests: XCTestCase {
    private func launch(_ extra: [String] = []) -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments = ["-ui-testing", "-store-in-memory", "-network", "offline"] + extra
        app.launch()
        return app
    }

    func testSelectAndSwitchExamOffline() {
        let app = launch()
        let beta = app.buttons["exam-test-beta"]
        XCTAssertTrue(beta.waitForExistence(timeout: 20))
        beta.tap()
        let picker = app.buttons["examPickerButton"]
        XCTAssertTrue(picker.waitForExistence(timeout: 10))
        XCTAssertEqual(picker.label, "BETA")
        picker.tap()
        let alpha = app.buttons["exam-test-alpha"]
        XCTAssertTrue(alpha.waitForExistence(timeout: 10))
        alpha.tap()
        XCTAssertTrue(app.buttons["examPickerButton"].waitForExistence(timeout: 10))
        XCTAssertEqual(app.buttons["examPickerButton"].label, "ALPHA")
        attachScreenshot(app, name: "Selected Alpha")
    }

    func testSingleFixtureSkipsPicker() {
        let app = launch(["-content-fixture", "test-beta", "-fixed-now", "2026-11-01T09:00:00Z"])
        let picker = app.buttons["examPickerButton"]
        XCTAssertTrue(picker.waitForExistence(timeout: 20))
        XCTAssertEqual(picker.label, "BETA")
        attachScreenshot(app, name: "Single fixture Beta")
    }

    func testHomeShowsEmptyStateAndLearningNavigation() {
        let app = launch(["-content-fixture", "test-beta"])
        XCTAssertTrue(app.staticTexts["homeNoData"].waitForExistence(timeout: 20))
        XCTAssertEqual(app.staticTexts["homeDueCards"].label, "0 枚")
        app.buttons["homeStartLearning"].tap()
        XCTAssertTrue(app.tabBars.buttons["試験"].isSelected)
        XCTAssertTrue(app.staticTexts["準備中"].waitForExistence(timeout: 5))
        app.tabBars.buttons["ホーム"].tap()
        XCTAssertTrue(app.staticTexts["homeNoData"].waitForExistence(timeout: 5))
        attachScreenshot(app, name: "Home empty state")
    }

    func testExamSwitchResetsTabNavigation() {
        let app = launch()
        XCTAssertTrue(app.buttons["exam-test-beta"].waitForExistence(timeout: 20))
        app.buttons["exam-test-beta"].tap()
        XCTAssertTrue(app.buttons["homeStartLearning"].waitForExistence(timeout: 10))
        app.buttons["homeStartLearning"].tap()
        app.tabBars.buttons["ホーム"].tap()
        app.buttons["examPickerButton"].tap()
        app.buttons["exam-test-alpha"].tap()
        XCTAssertTrue(app.staticTexts["homeNoData"].waitForExistence(timeout: 10))
        XCTAssertEqual(app.buttons["examPickerButton"].label, "ALPHA")
        XCTAssertTrue(app.tabBars.buttons["ホーム"].isSelected)
        app.tabBars.buttons["試験"].tap()
        XCTAssertEqual(app.navigationBars.buttons.count, 0)
    }

    func testInvalidLaunchArgumentsShowFailure() {
        let app = launch(["-fixed-now", "invalid"])
        XCTAssertTrue(app.staticTexts["データの読み込みに失敗しました。再インストールしてください"].waitForExistence(timeout: 15))
    }

    private func attachScreenshot(_ app: XCUIApplication, name: String) {
        let attachment = XCTAttachment(screenshot: app.screenshot())
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }
}
