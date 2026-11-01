import XCTest

/// 起動・試験選択と、各機能の画面ごとの確認。模試の通しと復元は ExamFlowUITests・ResumeUITests に置く。
@MainActor final class StartupTests: XCTestCase {
    func testSelectAndSwitchExamOffline() {
        let app = launchApp()
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
        let app = launchApp(["-content-fixture", "test-beta", "-fixed-now", "2026-11-01T09:00:00Z"])
        let picker = app.buttons["examPickerButton"]
        XCTAssertTrue(picker.waitForExistence(timeout: 20))
        XCTAssertEqual(picker.label, "BETA")
        attachScreenshot(app, name: "Single fixture Beta")
    }

    func testHomeShowsEmptyStateAndLearningNavigation() {
        let app = launchApp(["-content-fixture", "test-beta"])
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
        let app = launchApp()
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
        let app = launchApp(["-fixed-now", "invalid"])
        XCTAssertTrue(app.staticTexts["データの読み込みに失敗しました。再インストールしてください"].waitForExistence(timeout: 15))
    }

    func testResultExplanationAndCardActionsOffline() {
        let app = launchApp(["-content-fixture", "test-beta"])
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
        // SCR-090: 理由を選ぶまで送信できず、送信するとキューに保存される(送信は P5)
        let submit = app.buttons["report-submit"]
        XCTAssertTrue(submit.waitForExistence(timeout: 5))
        XCTAssertFalse(submit.isEnabled)
        app.buttons["正解が誤っている"].tap()
        XCTAssertTrue(submit.isEnabled)
        attachScreenshot(app, name: "Report sheet")
        // 注意文はコメント欄の下にあり、画面外では生成されないためスクロールして確認する
        let privacy = app.staticTexts["report-privacy"]
        reveal(privacy, in: app)
        XCTAssertEqual(privacy.label, "氏名・メールアドレスなどの個人情報は書かないでください")
        submit.tap()
        let message = app.staticTexts["report-message"]
        XCTAssertTrue(message.waitForExistence(timeout: 5))
        XCTAssertEqual(message.label, "報告を受け付けました。あとで送信します")
        attachScreenshot(app, name: "Report queued")
        app.buttons["report-close"].tap()
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
        XCTAssertTrue(app.staticTexts["ダミーの本文です。"].waitForExistence(timeout: 5))
    }

    func testLearnDocsIndexAndDocumentOffline() {
        let app = launchApp(["-content-fixture", "test-alpha"])
        XCTAssertTrue(app.tabBars.buttons["学ぶ"].waitForExistence(timeout: 20))
        app.tabBars.buttons["学ぶ"].tap()
        XCTAssertTrue(app.buttons["learn-module-docs"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.buttons["learn-module-cases"].exists)
        XCTAssertFalse(app.buttons["learn-module-trees"].exists)
        app.buttons["learn-module-docs"].tap()
        let available = app.buttons["doc-row-1.1"]
        XCTAssertTrue(available.waitForExistence(timeout: 5))
        XCTAssertTrue(app.buttons["doc-row-1.2"].label.contains("準備中"))
        XCTAssertFalse(app.buttons["doc-row-1.2"].isEnabled)
        attachScreenshot(app, name: "Docs index")
        available.tap()
        XCTAssertTrue(app.staticTexts["ダミーの本文です。"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["出典"].exists)
        XCTAssertTrue(app.buttons["doc-reference-0"].exists || app.links["doc-reference-0"].exists)
        attachScreenshot(app, name: "Document")
    }

    func testLearnCaseListDetailAndPracticeOffline() {
        let app = launchApp(["-content-fixture", "test-alpha"])
        XCTAssertTrue(app.tabBars.buttons["学ぶ"].waitForExistence(timeout: 20))
        app.tabBars.buttons["学ぶ"].tap()
        XCTAssertTrue(app.buttons["learn-module-cases"].waitForExistence(timeout: 5))
        app.buttons["learn-module-cases"].tap()
        // 試験定義の caseStudies(ehr, altostrat)の順
        let first = app.buttons["case-row-ehr"]
        let second = app.buttons["case-row-altostrat"]
        XCTAssertTrue(first.waitForExistence(timeout: 5))
        XCTAssertTrue(second.exists)
        XCTAssertLessThan(first.frame.minY, second.frame.minY)
        attachScreenshot(app, name: "Case list")
        first.tap()
        for header in ["要約", "ビジネス要件", "技術要件", "既存環境"] {
            XCTAssertTrue(app.staticTexts[header].waitForExistence(timeout: 5), header)
        }
        let official = app.buttons["case-official"].exists ? app.buttons["case-official"] : app.links["case-official"]
        XCTAssertTrue(official.exists)
        attachScreenshot(app, name: "Case detail")
        let practice = app.buttons["case-practice"]
        reveal(practice, in: app)
        practice.tap()
        XCTAssertTrue(app.navigationBars["練習"].waitForExistence(timeout: 5))
    }

    func testSettingsShuffleAndDeleteExamDataOffline() {
        let app = launchApp(["-content-fixture", "test-beta"])
        let open = app.buttons["settings-open"]
        XCTAssertTrue(open.waitForExistence(timeout: 20))
        open.tap()
        // SCR-002: シャッフルを ON にする
        let shuffle = app.switches["settings-shuffle"]
        XCTAssertTrue(shuffle.waitForExistence(timeout: 5))
        XCTAssertEqual(shuffle.value as? String, "0")
        shuffle.switches.firstMatch.tap()
        XCTAssertEqual(shuffle.value as? String, "1")
        let notice = app.staticTexts["settings-no-guarantee"]
        reveal(notice, in: app)
        XCTAssertTrue(notice.exists)
        attachScreenshot(app, name: "Settings")
        // この試験のデータを削除: 確認ダイアログで確定したときだけ削除し、ホームを作り直す
        let deleteExam = app.buttons["settings-delete-exam"]
        reveal(deleteExam, in: app)
        deleteExam.tap()
        let confirm = app.buttons["settings-delete-confirm"].firstMatch
        XCTAssertTrue(confirm.waitForExistence(timeout: 5))
        attachScreenshot(app, name: "Settings delete confirmation")
        confirm.tap()
        // シートが閉じるのを待つ(閉じる途中では背後のホームのボタンも見えている)
        XCTAssertTrue(app.buttons["settings-close"].waitForNonExistence(timeout: 10))
        XCTAssertTrue(open.isHittable)
        // 試験のデータ削除では設定(シャッフル)は残る
        open.tap()
        XCTAssertTrue(shuffle.waitForExistence(timeout: 5))
        XCTAssertEqual(shuffle.value as? String, "1")
    }

    func testAnalyticsShowsDomainsWithoutAnswersOffline() {
        let app = launchApp(["-content-fixture", "test-beta"])
        XCTAssertTrue(app.tabBars.buttons["分析"].waitForExistence(timeout: 20))
        app.tabBars.buttons["分析"].tap()
        XCTAssertTrue(app.staticTexts["analytics-empty"].waitForExistence(timeout: 5))
        // test-beta の4ドメインを、解答なし(0% ではなく「—」)で出す
        for id in 1...4 {
            let row = app.descendants(matching: .any)["analytics-domain-\(id)"]
            reveal(row, in: app)
            XCTAssertTrue(row.exists, "domain \(id)")
            XCTAssertTrue(row.label.contains("—"), row.label)
        }
        XCTAssertFalse(app.descendants(matching: .any)["analytics-domain-5"].exists)
        attachScreenshot(app, name: "Analytics")
    }

    func testPracticeFeedbackAndResultOffline() {
        let app = launchApp(["-content-fixture", "test-beta"])
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

    func testFlashcardDeckStudyAndFinishOffline() {
        let app = launchApp(["-content-fixture", "test-beta"])
        XCTAssertTrue(app.tabBars.buttons["カード"].waitForExistence(timeout: 20))
        app.tabBars.buttons["カード"].tap()
        let deck = app.buttons["deck-all"]
        XCTAssertTrue(deck.waitForExistence(timeout: 5))
        XCTAssertTrue(deck.label.contains("今日 2 枚"))
        deck.tap()
        for _ in 0..<2 {
            XCTAssertTrue(app.staticTexts["card-front"].waitForExistence(timeout: 5))
            app.buttons["card-flip"].tap()
            let easy = app.buttons["card-rate-easy"]
            XCTAssertTrue(easy.waitForExistence(timeout: 5))
            XCTAssertTrue(easy.label.contains("簡単") && easy.label.contains("日"), easy.label)
            easy.tap()
        }
        XCTAssertTrue(app.staticTexts["card-finished-count"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["card-finished-count"].label.contains("2 枚を学習しました"))
        attachScreenshot(app, name: "Flashcard finished")
        app.buttons["card-back-to-decks"].tap()
        XCTAssertTrue(app.buttons["deck-all"].waitForExistence(timeout: 5))
        let refreshed = NSPredicate(format: "label CONTAINS %@", "今日 0 枚")
        expectation(for: refreshed, evaluatedWith: app.buttons["deck-all"])
        waitForExpectations(timeout: 5)
    }
}
