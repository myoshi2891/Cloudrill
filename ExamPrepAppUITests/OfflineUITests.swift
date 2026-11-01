import XCTest

/// 通信なしで主要機能を順に使えること(AC-04、NFR-03)。機能ごとの詳しい確認は各テストに任せる。
@MainActor final class OfflineUITests: XCTestCase {
    override func setUp() { continueAfterFailure = false }

    func testAllFeaturesOffline() {
        let app = launchApp(["-content-fixture", "test-alpha"])
        // 模試: 開始して1問に解答する
        let exam = ExamScreen(app: app, test: self)
        exam.open(examSet: 1)
        exam.start()
        exam.answerCurrent()
        // 練習: 1問に解答して解説まで
        app.tabBars.buttons["ホーム"].tap()
        let startLearning = app.buttons["homeStartLearning"]
        XCTAssertTrue(startLearning.waitForExistence(timeout: 10))
        startLearning.tap()
        XCTAssertTrue(app.navigationBars["練習"].waitForExistence(timeout: 5))
        let practiceStart = app.buttons["practice-start"]
        reveal(practiceStart, in: app)
        practiceStart.tap()
        let practiceChoice = app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH %@", "session-choice-")).firstMatch
        XCTAssertTrue(practiceChoice.waitForExistence(timeout: 5))
        let required = app.staticTexts["session-required"]
        if required.exists && required.label.hasPrefix("2") {
            app.buttons["session-choice-a"].tap(); app.buttons["session-choice-b"].tap()
        } else {
            practiceChoice.tap()
        }
        let submit = app.buttons["practice-submit"]
        reveal(submit, in: app)
        submit.tap()
        XCTAssertTrue(app.staticTexts["explanation-stem"].waitForExistence(timeout: 5))
        // カード: デッキを開いて1枚学習する
        app.tabBars.buttons["カード"].tap()
        let deck = app.buttons["deck-all"]
        XCTAssertTrue(deck.waitForExistence(timeout: 5))
        deck.tap()
        XCTAssertTrue(app.staticTexts["card-front"].waitForExistence(timeout: 5))
        app.buttons["card-flip"].tap()
        let easy = app.buttons["card-rate-easy"]
        XCTAssertTrue(easy.waitForExistence(timeout: 5))
        easy.tap()
        // ドキュメント: 1.1 の本文を開く
        app.tabBars.buttons["学ぶ"].tap()
        let docs = app.buttons["learn-module-docs"]
        XCTAssertTrue(docs.waitForExistence(timeout: 5))
        docs.tap()
        let doc = app.buttons["doc-row-1.1"]
        XCTAssertTrue(doc.waitForExistence(timeout: 5))
        doc.tap()
        XCTAssertTrue(app.staticTexts["ダミーの本文です。"].waitForExistence(timeout: 5))
        attachScreenshot(app, name: "Offline document")
    }
}
