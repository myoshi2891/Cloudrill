import XCTest

/// 強制終了からの復元(AC-02)。
@MainActor final class ResumeUITests: XCTestCase {
    override func setUp() { continueAfterFailure = false }

    func testResumeAfterTermination() {
        // Arrange: 保存先を指定し、test-beta(40問・90分)で5問に解答、1問目にフラグを付ける
        let store = UITestLaunch.storePath()
        defer { try? FileManager.default.removeItem(atPath: store) }
        let args = UITestLaunch.base + ["-content-fixture", "test-beta", "-store-path", store]
        let app = XCUIApplication()
        app.launchArguments = args
        app.launch()
        let exam = ExamScreen(app: app, test: self)
        exam.open(examSet: 1)
        exam.start()
        XCTAssertEqual(exam.timer.label, "残り 90 分")
        for number in 1...5 {
            exam.answerCurrent()
            if number == 1 { exam.toggleFlag() }
            exam.next()
        }
        XCTAssertEqual(exam.progress.label, "問題 6 / 40")
        // Act: 強制終了し、10分後の時刻で同じ保存先から起動する
        app.terminate()
        app.launchArguments = args + ["-advance-on-launch", "600"]
        app.launch()
        exam.resumeFromHome()
        // Assert: 位置・残り時間(終了中の10分を引いた値)・5問の解答とフラグが戻る
        XCTAssertTrue(exam.progress.waitForExistence(timeout: 10))
        XCTAssertEqual(exam.progress.label, "問題 6 / 40")
        XCTAssertEqual(exam.timer.label, "残り 80 分")
        attachScreenshot(app, name: "Resumed exam")
        let review = exam.openReview()
        XCTAssertEqual(review.counts.label, "未解答 35 問、見直し 1 問")
        review.jump(to: 1)
        XCTAssertTrue(exam.progress.waitForExistence(timeout: 5))
        XCTAssertTrue(exam.choice("a").label.contains("選択済み"))
        XCTAssertEqual(app.buttons["session-flag"].label, "見直しフラグを外す")
    }
}
