import XCTest

/// UI テストの共通の起動引数。時計は -fixed-now(既定 2026-11-01T09:00:00Z)で固定し、通信は使わない。
enum UITestLaunch {
    static let base = ["-ui-testing", "-network", "offline"]
    static let inMemory = base + ["-store-in-memory"]

    /// 終了をまたぐテスト用の保存先。テストの終わりに削除する。
    static func storePath() -> String { "/tmp/cloudrill-ui-\(UUID().uuidString)" }
}

extension XCTestCase {
    @MainActor func launchApp(_ extra: [String] = []) -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments = UITestLaunch.inMemory + extra
        app.launch()
        return app
    }

    /// 画面外の要素は List・Form で生成されないため、見えるまで上にスクロールする。
    @MainActor func reveal(_ element: XCUIElement, in app: XCUIApplication) {
        for _ in 0..<12 {
            if element.exists && element.isHittable { return }
            app.swipeUp()
        }
    }

    @MainActor func attachScreenshot(_ app: XCUIApplication, name: String) {
        let attachment = XCTAttachment(screenshot: app.screenshot())
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }
}

/// 模試の開始確認と解答画面(SCR-011・SCR-012)の操作。
@MainActor struct ExamScreen {
    let app: XCUIApplication
    let test: XCTestCase

    var progress: XCUIElement { app.staticTexts["session-progress"] }
    var timer: XCUIElement { app.descendants(matching: .any)["session-timer"] }
    var format: XCUIElement { app.staticTexts["exam-format"] }
    var submitted: XCUIElement { app.staticTexts["session-submitted"] }
    func choice(_ id: String) -> XCUIElement { app.buttons["session-choice-\(id)"] }

    /// 試験タブから模試の開始確認を開く。
    func open(examSet: Int) {
        let tab = app.tabBars.buttons["試験"]
        XCTAssertTrue(tab.waitForExistence(timeout: 20))
        tab.tap()
        let set = app.buttons["exam-set-\(examSet)"]
        XCTAssertTrue(set.waitForExistence(timeout: 5))
        set.tap()
        XCTAssertTrue(app.buttons["exam-start"].waitForExistence(timeout: 5))
    }

    func start() {
        app.buttons["exam-start"].tap()
        XCTAssertTrue(progress.waitForExistence(timeout: 10))
    }

    /// ホームの「再開」から解答画面へ戻る。
    func resumeFromHome() {
        let resume = app.buttons["homeResume"]
        XCTAssertTrue(resume.waitForExistence(timeout: 20))
        resume.tap()
    }

    /// 表示中の問題に、必要な数(「Nつ選択」)だけ先頭から選んで解答する。
    func answerCurrent() {
        let required = app.staticTexts["session-required"]
        XCTAssertTrue(required.waitForExistence(timeout: 5))
        let count = required.label.hasPrefix("2") ? 2 : 1
        for id in ["a", "b"].prefix(count) {
            let target = choice(id)
            test.reveal(target, in: app)
            target.tap()
            XCTAssertTrue(target.label.contains("選択済み"), target.label)
        }
    }

    func toggleFlag() { tapScrolled(app.buttons["session-flag"]) }
    func next() { tapScrolled(app.buttons["session-next"]) }
    func previous() { tapScrolled(app.buttons["session-previous"]) }

    func openReview() -> ReviewScreen {
        tapScrolled(app.buttons["session-review"])
        let review = ReviewScreen(app: app)
        XCTAssertTrue(review.counts.waitForExistence(timeout: 5))
        return review
    }

    private func tapScrolled(_ element: XCUIElement) {
        test.reveal(element, in: app)
        element.tap()
    }
}

/// 見直し一覧(SCR-013)の操作。
@MainActor struct ReviewScreen {
    let app: XCUIApplication

    var counts: XCUIElement { app.staticTexts["review-counts"] }
    var dialog: XCUIElement { app.alerts.firstMatch }

    func jump(to number: Int) { app.buttons["review-question-\(number)"].tap() }

    /// 提出ボタンを押し、確認ダイアログを待つ。
    func submit() {
        app.buttons["review-submit"].tap()
        XCTAssertTrue(dialog.waitForExistence(timeout: 5))
    }
    func confirm() { dialog.buttons["review-confirm"].firstMatch.tap() }
    func cancel() { dialog.buttons["キャンセル"].tap() }
}
