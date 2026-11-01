import XCTest

/// 起動時間の記録(NFR-01)。Simulator では記録だけを行い、2秒以内かどうかは実機で確認する。
@MainActor final class LaunchPerformanceTests: XCTestCase {
    func testLaunchPerformance() {
        let app = XCUIApplication()
        app.launchArguments = UITestLaunch.inMemory + ["-content-fixture", "test-alpha"]
        measure(metrics: [XCTApplicationLaunchMetric(waitUntilResponsive: true)]) {
            app.launch()
        }
    }

    /// LaunchMetric は非同期のパック読み込み完了を保証しないため、操作可能な画面も別に測る。
    /// XCTest の起動・問い合わせの時間を含む参考値。NFR-01 の実機判定には使わない。
    func testLaunchToExamPickerPerformance() {
        let app = XCUIApplication()
        app.launchArguments = UITestLaunch.inMemory
        let options = XCTMeasureOptions()
        options.iterationCount = 5
        options.invocationOptions = [.manuallyStop]
        measure(metrics: [XCTClockMetric()], options: options) {
            app.launch()
            let exam = app.buttons["exam-test-alpha"]
            XCTAssertTrue(exam.waitForExistence(timeout: 20))
            XCTAssertTrue(exam.isHittable)
            stopMeasuring()
            app.terminate()
        }
    }
}
