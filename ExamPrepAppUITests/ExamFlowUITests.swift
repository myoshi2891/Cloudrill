import XCTest

/// 模試の通しの流れ(AC-01)と、試験ごとの形の違い。
@MainActor final class ExamFlowUITests: XCTestCase {
    override func setUp() { continueAfterFailure = false }

    func testCompleteExamAndSubmit() {
        // Arrange: test-alpha の模試1(55問。複数選択を含む)
        let app = launchApp(["-content-fixture", "test-alpha"])
        let exam = ExamScreen(app: app, test: self)
        exam.open(examSet: 1)
        XCTAssertEqual(exam.format.label, "55 問・120 分")
        exam.start()
        // Act: 全問に解答し、見直しから提出する
        for number in 1...55 {
            XCTAssertEqual(exam.progress.label, "問題 \(number) / 55")
            exam.answerCurrent()
            if number < 55 { exam.next() }
        }
        let review = exam.openReview()
        XCTAssertEqual(review.counts.label, "未解答 0 問、見直し 0 問")
        review.submit()
        review.confirm()
        // Assert: 結果画面
        XCTAssertTrue(exam.submitted.waitForExistence(timeout: 10))
        XCTAssertEqual(exam.submitted.label, "模試を提出しました")
        // 正答数は fixture の正解次第なので、全55問が採点対象であることだけを確認する(例: 「12 / 55 (22%)」)
        XCTAssertTrue(app.staticTexts["result-score"].label.contains(" / 55 ("), app.staticTexts["result-score"].label)
        attachScreenshot(app, name: "Completed exam result")
    }

    func testAutoSubmitOnTimeout() {
        // Arrange: 保存先を指定して開始し、1問に解答して終了する
        let store = UITestLaunch.storePath()
        defer { try? FileManager.default.removeItem(atPath: store) }
        let args = UITestLaunch.base + ["-content-fixture", "test-alpha", "-store-path", store]
        let app = XCUIApplication()
        app.launchArguments = args
        app.launch()
        let exam = ExamScreen(app: app, test: self)
        exam.open(examSet: 1)
        exam.start()
        exam.answerCurrent()
        app.terminate()
        // Act: 120 分を過ぎた時刻で起動し直す
        app.launchArguments = args + ["-advance-on-launch", "7201"]
        app.launch()
        exam.resumeFromHome()
        // Assert: 自動で提出され、結果画面になる
        XCTAssertTrue(exam.submitted.waitForExistence(timeout: 10))
        XCTAssertEqual(exam.submitted.label, "制限時間を過ぎたため提出しました")
        XCTAssertTrue(app.staticTexts["result-score"].exists)
        attachScreenshot(app, name: "Expired exam submission")
    }

    func testBetaExamHasNoCaseUI() {
        let app = launchApp(["-content-fixture", "test-beta"])
        // 学ぶタブにケースがない
        let learn = app.tabBars.buttons["学ぶ"]
        XCTAssertTrue(learn.waitForExistence(timeout: 20))
        learn.tap()
        XCTAssertTrue(app.buttons["learn-module-docs"].waitForExistence(timeout: 5))
        XCTAssertFalse(app.buttons["learn-module-cases"].exists)
        // 開始確認は「40 問・90 分」で、ケースの表示がない
        let exam = ExamScreen(app: app, test: self)
        exam.open(examSet: 1)
        XCTAssertEqual(exam.format.label, "40 問・90 分")
        XCTAssertFalse(app.staticTexts["出題されるケース"].exists)
        attachScreenshot(app, name: "Beta exam confirmation")
        exam.start()
        XCTAssertEqual(exam.progress.label, "問題 1 / 40")
        XCTAssertFalse(app.buttons["session-case"].exists)
        exam.answerCurrent()
        // 解答中の模試はホームから再開できる
        app.tabBars.buttons["ホーム"].tap()
        XCTAssertTrue(app.buttons["homeResume"].waitForExistence(timeout: 10))
    }

    func testReviewJumpCancelAndManualSubmission() {
        let app = launchApp(["-content-fixture", "test-beta"])
        let exam = ExamScreen(app: app, test: self)
        exam.open(examSet: 1)
        exam.start()
        exam.answerCurrent()
        exam.toggleFlag()
        var review = exam.openReview()
        XCTAssertEqual(review.counts.label, "未解答 39 問、見直し 1 問")
        attachScreenshot(app, name: "Exam review unanswered and flagged")
        review.jump(to: 2)
        XCTAssertTrue(exam.progress.waitForExistence(timeout: 5))
        XCTAssertEqual(exam.progress.label, "問題 2 / 40")
        review = exam.openReview()
        review.submit()
        XCTAssertTrue(review.dialog.staticTexts["未解答 39 問、見直し 1 問"].exists)
        review.cancel()
        XCTAssertTrue(review.counts.exists)
        review.submit()
        review.confirm()
        XCTAssertTrue(exam.submitted.waitForExistence(timeout: 10))
        XCTAssertEqual(exam.submitted.label, "模試を提出しました")
        attachScreenshot(app, name: "Manually submitted exam")
        app.tabBars.buttons["ホーム"].tap()
        XCTAssertTrue(app.buttons["homeStartLearning"].waitForExistence(timeout: 5))
        XCTAssertFalse(app.buttons["homeResume"].exists)
    }
}
