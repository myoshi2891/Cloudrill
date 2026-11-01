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
}
