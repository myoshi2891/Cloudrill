import Foundation
import Testing
import DomainTestSupport
import StudyModels
@testable import ExamEngine

@Suite("ExamTimer")
struct ExamTimerTests {
    private let start = Date(timeIntervalSince1970: 1_793_527_200)  // 2026-11-01T10:00:00Z

    private func minutes(_ value: Int) -> Duration { .seconds(value * 60) }

    private func at(minutes value: Int) -> Date { start.addingTimeInterval(TimeInterval(value * 60)) }

    @Test("残り時間は期限から現在時刻を引いた値")
    func remainingIsDeadlineMinusNow() {
        // Arrange
        let timer = ExamTimer(startedAt: start, duration: minutes(120))
        // Act / Assert
        #expect(timer.remaining(at: at(minutes: 30)) == minutes(90))
        #expect(!timer.isExpired(at: at(minutes: 30)))
    }

    @Test("期限を過ぎても残り時間は負にならない")
    func remainingNeverNegative() {
        // Arrange
        let timer = ExamTimer(startedAt: start, duration: minutes(120))
        // Act / Assert
        #expect(timer.remaining(at: at(minutes: 125)) == .zero)
        #expect(timer.isExpired(at: at(minutes: 125)))
    }

    @Test("期限ちょうどで期限切れ")
    func expiredExactlyAtDeadline() {
        // Arrange
        let timer = ExamTimer(startedAt: start, duration: minutes(120))
        // Act / Assert
        #expect(timer.isExpired(at: at(minutes: 120)))
    }

    @Test("一時停止中は残り時間が減らない")
    func pauseKeepsRemaining() {
        // Arrange
        var timer = ExamTimer(startedAt: start, duration: minutes(120))
        // Act
        timer.pause(at: at(minutes: 30))
        // Assert
        #expect(timer.remaining(at: at(minutes: 90)) == minutes(90))
        #expect(!timer.isExpired(at: at(minutes: 200)))
    }

    @Test("再開すると、残り時間から期限を計算し直す")
    func resumeRecomputesDeadline() {
        // Arrange
        var timer = ExamTimer(startedAt: start, duration: minutes(120))
        timer.pause(at: at(minutes: 30))
        // Act
        timer.resume(at: at(minutes: 120))  // 12:00
        // Assert
        #expect(timer.deadline == at(minutes: 120 + 90))
        #expect(timer.pausedRemaining == nil)
    }

    @Test("既定のポリシーでは中断中も時間が経過する(本番と同じ)")
    func noPauseByDefault() throws {
        // Arrange
        var session = ExamSession(order: makeOrder(count: 3), duration: minutes(120), timerPolicy: ExamTimerPolicy())
        try session.handle(.start, at: start)
        try session.handle(.suspend, at: at(minutes: 30))
        // Act
        try session.handle(.resume, at: at(minutes: 90))
        // Assert
        #expect(session.state == .inProgress)
        #expect(session.timer?.remaining(at: at(minutes: 90)) == minutes(30))
    }

    /// 残り時間(秒)の組で表した、しきい値の通過
    struct ThresholdCase: Sendable, CustomTestStringConvertible {
        var previousRemaining: Int
        var currentRemaining: Int
        var expected: Duration?

        var testDescription: String { "\(previousRemaining)s → \(currentRemaining)s" }
    }

    @Test("前回から今回までに越えたしきい値を返す", arguments: [
        ThresholdCase(previousRemaining: 601, currentRemaining: 599, expected: .seconds(600)),
        ThresholdCase(previousRemaining: 301, currentRemaining: 299, expected: .seconds(300)),
        ThresholdCase(previousRemaining: 540, currentRemaining: 480, expected: nil),
        ThresholdCase(previousRemaining: 10, currentRemaining: 0, expected: nil),
        ThresholdCase(previousRemaining: 601, currentRemaining: 600, expected: .seconds(600)),  // ちょうど到達
        ThresholdCase(previousRemaining: 601, currentRemaining: 299, expected: .seconds(300)),  // 2つ越えたら短い方
    ])
    func crossedThreshold(testCase: ThresholdCase) {
        // Arrange
        let timer = ExamTimer(startedAt: start, duration: minutes(120))
        let policy = ExamTimerPolicy(warningThresholds: [.seconds(600), .seconds(300)])
        let previous = timer.deadline.addingTimeInterval(-TimeInterval(testCase.previousRemaining))
        let now = timer.deadline.addingTimeInterval(-TimeInterval(testCase.currentRemaining))
        // Act
        let crossed = timer.crossedThreshold(from: previous, to: now, policy: policy)
        // Assert
        #expect(crossed == testCase.expected)
    }

    @Test("試験時間は試験定義から取る")
    func durationComesFromDefinition() {
        // Act
        let timer = ExamTimer(startedAt: start, definition: ExamDefinitionBuilder.betaLike().build())
        // Assert
        #expect(timer.duration == minutes(90))
        #expect(timer.deadline == at(minutes: 90))
    }

    @Test("中断中に期限が過ぎていれば、再開した時点で自動で提出する(E-06)")
    func resumeAfterExpiryAutoSubmits() throws {
        // Arrange
        var session = ExamSession(order: makeOrder(count: 3), duration: minutes(120), timerPolicy: ExamTimerPolicy())
        try session.handle(.start, at: start)
        try session.handle(.suspend, at: at(minutes: 30))
        // Act
        try session.handle(.resume, at: at(minutes: 150))
        // Assert
        #expect(session.state == .submitted(.timeExpired))
    }
}
