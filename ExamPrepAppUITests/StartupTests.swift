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
        XCTAssertTrue(app.navigationBars["練習"].waitForExistence(timeout: 5))
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

    func testBetaExamStartAndResumeBanner() {
        let app = launch(["-content-fixture", "test-beta"])
        XCTAssertTrue(app.buttons["homeStartLearning"].waitForExistence(timeout: 20))
        app.tabBars.buttons["試験"].tap()
        app.buttons["exam-set-1"].tap()
        XCTAssertTrue(app.staticTexts["exam-format"].waitForExistence(timeout: 5))
        XCTAssertEqual(app.staticTexts["exam-format"].label, "40 問・90 分")
        XCTAssertFalse(app.staticTexts["出題されるケース"].exists)
        attachScreenshot(app, name: "Beta exam confirmation")
        app.buttons["exam-start"].tap()
        XCTAssertTrue(app.staticTexts["session-progress"].waitForExistence(timeout: 10))
        XCTAssertEqual(app.staticTexts["session-progress"].label, "問題 1 / 40")
        XCTAssertFalse(app.buttons["session-case"].exists)
        let choice = app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH %@", "session-choice-")).firstMatch
        XCTAssertTrue(choice.waitForExistence(timeout: 5))
        choice.tap()
        XCTAssertTrue(choice.label.contains("選択済み"))
        attachScreenshot(app, name: "Beta answer selected")
        app.tabBars.buttons["ホーム"].tap()
        XCTAssertTrue(app.buttons["homeResume"].waitForExistence(timeout: 10))
    }

    func testAnswerRestoresAfterTerminationAndExpiresOnRelaunch() {
        let app = XCUIApplication()
        let store = "/tmp/cloudrill-session-ui-\(UUID().uuidString)"
        defer { try? FileManager.default.removeItem(atPath: store) }
        let args = ["-ui-testing", "-content-fixture", "test-beta", "-store-path", store,
                    "-fixed-now", "2026-11-01T09:00:00Z", "-network", "offline"]
        app.launchArguments = args
        app.launch()
        XCTAssertTrue(app.buttons["homeStartLearning"].waitForExistence(timeout: 20))
        app.tabBars.buttons["試験"].tap()
        app.buttons["exam-set-1"].tap()
        XCTAssertTrue(app.buttons["exam-start"].waitForExistence(timeout: 5))
        app.buttons["exam-start"].tap()
        XCTAssertTrue(app.staticTexts["session-progress"].waitForExistence(timeout: 10))
        let choice = app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH %@", "session-choice-")).firstMatch
        let choiceID = choice.identifier
        choice.tap()
        XCTAssertTrue(choice.label.contains("選択済み"))
        let flag = app.buttons["session-flag"]
        if !flag.isHittable { app.swipeUp() }
        flag.tap()
        app.buttons["session-next"].tap()
        XCTAssertEqual(app.staticTexts["session-progress"].label, "問題 2 / 40")
        app.terminate()
        app.launchArguments = args + ["-advance-on-launch", "61"]
        app.launch()
        XCTAssertTrue(app.buttons["homeResume"].waitForExistence(timeout: 20))
        app.buttons["homeResume"].tap()
        XCTAssertTrue(app.staticTexts["session-progress"].waitForExistence(timeout: 10))
        XCTAssertEqual(app.staticTexts["session-progress"].label, "問題 2 / 40")
        let previous = app.buttons["session-previous"]
        if !previous.isHittable { app.swipeUp() }
        previous.tap()
        XCTAssertTrue(app.buttons[choiceID].label.contains("選択済み"))
        XCTAssertEqual(app.buttons["session-flag"].label, "見直しフラグを外す")
        app.terminate()
        app.launchArguments = args + ["-advance-on-launch", "5401"]
        app.launch()
        XCTAssertTrue(app.buttons["homeResume"].waitForExistence(timeout: 20))
        app.buttons["homeResume"].tap()
        XCTAssertTrue(app.staticTexts["session-submitted"].waitForExistence(timeout: 10))
        XCTAssertEqual(app.staticTexts["session-submitted"].label, "制限時間を過ぎたため提出しました")
        attachScreenshot(app, name: "Expired exam submission")
    }

    func testReviewJumpCancelAndManualSubmission() {
        let app = launch(["-content-fixture", "test-beta"])
        XCTAssertTrue(app.buttons["homeStartLearning"].waitForExistence(timeout: 20))
        app.tabBars.buttons["試験"].tap()
        app.buttons["exam-set-1"].tap()
        app.buttons["exam-start"].tap()
        XCTAssertTrue(app.buttons["session-choice-a"].waitForExistence(timeout: 10))
        app.buttons["session-choice-a"].tap()
        app.buttons["session-flag"].tap()
        let reviewButton = app.buttons["session-review"]
        if !reviewButton.isHittable { app.swipeUp() }
        reviewButton.tap()
        XCTAssertTrue(app.staticTexts["review-counts"].waitForExistence(timeout: 5))
        XCTAssertEqual(app.staticTexts["review-counts"].label, "未解答 39 問、見直し 1 問")
        attachScreenshot(app, name: "Exam review unanswered and flagged")
        app.buttons["review-question-2"].tap()
        XCTAssertTrue(app.staticTexts["session-progress"].waitForExistence(timeout: 5))
        XCTAssertEqual(app.staticTexts["session-progress"].label, "問題 2 / 40")
        if !reviewButton.isHittable { app.swipeUp() }
        reviewButton.tap()
        XCTAssertTrue(app.buttons["review-submit"].waitForExistence(timeout: 5))
        app.buttons["review-submit"].tap()
        let dialog = app.alerts.firstMatch
        XCTAssertTrue(dialog.waitForExistence(timeout: 5))
        XCTAssertTrue(dialog.staticTexts["未解答 39 問、見直し 1 問"].exists)
        dialog.buttons["キャンセル"].tap()
        XCTAssertTrue(app.staticTexts["review-counts"].exists)
        app.buttons["review-submit"].tap()
        XCTAssertTrue(dialog.waitForExistence(timeout: 5))
        dialog.buttons["review-confirm"].firstMatch.tap()
        XCTAssertTrue(app.staticTexts["session-submitted"].waitForExistence(timeout: 10))
        XCTAssertEqual(app.staticTexts["session-submitted"].label, "模試を提出しました")
        attachScreenshot(app, name: "Manually submitted exam")
        app.tabBars.buttons["ホーム"].tap()
        XCTAssertTrue(app.buttons["homeStartLearning"].waitForExistence(timeout: 5))
        XCTAssertFalse(app.buttons["homeResume"].exists)
    }

    func testInvalidLaunchArgumentsShowFailure() {
        let app = launch(["-fixed-now", "invalid"])
        XCTAssertTrue(app.staticTexts["データの読み込みに失敗しました。再インストールしてください"].waitForExistence(timeout: 15))
    }

    func testResultExplanationAndCardActionsOffline() {
        let app = launch(["-content-fixture", "test-beta"])
        XCTAssertTrue(app.buttons["homeStartLearning"].waitForExistence(timeout: 20))
        app.tabBars.buttons["試験"].tap()
        app.buttons["exam-set-1"].tap()
        app.buttons["exam-start"].tap()
        XCTAssertTrue(app.staticTexts["session-progress"].waitForExistence(timeout: 10))
        let review = app.buttons["session-review"]
        reveal(review, in: app)
        review.tap()
        app.buttons["review-submit"].tap()
        app.alerts.buttons["review-confirm"].firstMatch.tap()
        XCTAssertTrue(app.staticTexts["result-score"].waitForExistence(timeout: 10))
        XCTAssertEqual(app.staticTexts["result-score"].label, "0 / 40 (0%)")
        XCTAssertTrue(app.staticTexts["ドメイン別正答率"].exists)
        XCTAssertFalse(app.staticTexts["ケース別正答率"].exists)
        attachScreenshot(app, name: "Detailed exam result")
        let first = app.buttons["result-question-1"]
        reveal(first, in: app)
        first.tap()
        XCTAssertTrue(app.staticTexts["explanation-stem"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["未解答"].exists)
        app.buttons["explanation-language"].tap()
        XCTAssertEqual(app.buttons["explanation-language"].label, "日本語で読む")
        app.buttons["explanation-language"].tap()
        for id in ["a", "b", "c", "d"] {
            let rationale = app.staticTexts["explanation-rationale-\(id)"]
            reveal(rationale, in: app)
            XCTAssertTrue(rationale.exists)
        }
        let addCard = app.buttons["explanation-add-card"]
        reveal(addCard, in: app)
        addCard.tap()
        XCTAssertTrue(app.buttons["追加済み"].waitForExistence(timeout: 5))
        XCTAssertFalse(addCard.isEnabled)
        attachScreenshot(app, name: "Explanation references and card added")
        app.buttons["explanation-report"].tap()
        XCTAssertTrue(app.staticTexts["誤り報告の受付は準備中です。"].waitForExistence(timeout: 5))
        app.buttons["閉じる"].tap()
        // fixture の問題1には資料がなく、問題13 (NET.1) にだけ関連資料がある。
        XCTAssertFalse(app.buttons["explanation-related-doc"].exists)
        app.buttons["BackButton"].tap()
        let withDoc = app.buttons["result-question-13"]
        reveal(withDoc, in: app)
        withDoc.tap()
        XCTAssertTrue(app.staticTexts["explanation-stem"].waitForExistence(timeout: 5))
        let relatedDoc = app.buttons["explanation-related-doc"]
        reveal(relatedDoc, in: app)
        relatedDoc.tap()
        XCTAssertTrue(app.tabBars.buttons["学ぶ"].isSelected)
    }

    func testPracticeFeedbackAndResultOffline() {
        let app = launch(["-content-fixture", "test-beta"])
        XCTAssertTrue(app.buttons["homeStartLearning"].waitForExistence(timeout: 20))
        app.buttons["homeStartLearning"].tap()
        XCTAssertTrue(app.navigationBars["練習"].waitForExistence(timeout: 5))
        XCTAssertFalse(app.staticTexts["ケース（未選択ならすべて）"].exists)
        let start = app.buttons["practice-start"]
        reveal(start, in: app)
        start.tap()
        for _ in 0..<10 {
            let choice = app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH %@", "session-choice-")).firstMatch
            XCTAssertTrue(choice.waitForExistence(timeout: 5))
            choice.tap()
            let submit = app.buttons["practice-submit"]
            reveal(submit, in: app)
            submit.tap()
            XCTAssertTrue(app.staticTexts["explanation-stem"].waitForExistence(timeout: 5))
            XCTAssertTrue(app.staticTexts["explanation-rationale-a"].exists)
            app.buttons["practice-next"].tap()
        }
        XCTAssertTrue(app.staticTexts["practice-score"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["practice-score"].label.contains("/ 10 問正解"))
        attachScreenshot(app, name: "Practice result")
    }

    private func reveal(_ element: XCUIElement, in app: XCUIApplication) {
        for _ in 0..<12 {
            if element.exists && element.isHittable { return }
            app.swipeUp()
        }
    }

    private func attachScreenshot(_ app: XCUIApplication, name: String) {
        let attachment = XCTAttachment(screenshot: app.screenshot())
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }
}
