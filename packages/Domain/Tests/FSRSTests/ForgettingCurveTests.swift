import Foundation
import Testing
@testable import FSRS

@Suite("ForgettingCurve")
struct ForgettingCurveTests {
    private let fsrs6 = ForgettingCurve(decay: -FSRSParameters.defaultWeights[20])
    private let fsrs5 = ForgettingCurve.fsrs5

    @Test("t = S のとき R = 0.9(FSRS-5 と FSRS-6 の両方)", arguments: [1.0, 10.0, 100.0])
    func retrievabilityAtStabilityIsNinetyPercent(stability: Double) {
        // Act / Assert
        #expect(relativelyEqual(fsrs6.retrievability(elapsedDays: stability, stability: stability), 0.9))
        #expect(relativelyEqual(fsrs5.retrievability(elapsedDays: stability, stability: stability), 0.9))
    }

    @Test("FSRS-5 は DECAY = -0.5、FACTOR = 19/81")
    func fsrs5Constants() {
        #expect(fsrs5.decay == -0.5)
        #expect(relativelyEqual(fsrs5.factor, 19.0 / 81.0))
    }

    @Test("FSRS-6 は DECAY = -w[20]")
    func fsrs6DecayComesFromParameters() throws {
        // Arrange
        let parameters = try FSRSParameters()
        // Act
        let curve = ForgettingCurve(parameters: parameters)
        // Assert
        #expect(curve.decay == -parameters.w[20])
        #expect(curve == fsrs6)
    }

    @Test("t = 0 のとき R = 1")
    func retrievabilityAtZeroIsOne() {
        #expect(fsrs6.retrievability(elapsedDays: 0, stability: 5) == 1)
    }

    @Test("経過日数とともに単調に減少する")
    func retrievabilityDecreases() {
        // Act
        let values = (0...30).map { fsrs6.retrievability(elapsedDays: Double($0), stability: 5) }
        // Assert
        #expect(zip(values, values.dropFirst()).allSatisfy { $0 > $1 })
    }

    @Test("目標保持率 0.9 の間隔は安定度と等しい", arguments: [1.0, 7.5, 42.0])
    func intervalForNinetyPercentIsStability(stability: Double) {
        // Act / Assert
        #expect(relativelyEqual(fsrs6.rawInterval(desiredRetention: 0.9, stability: stability), stability))
        #expect(fsrs6.interval(desiredRetention: 0.9, stability: 42, maximumInterval: 36500) == 42)
    }

    @Test("間隔は日単位に丸め、1 日以上・上限以下にする", arguments: [
        (0.3, 1),
        (40000.0, 36500),
    ])
    func intervalRoundsAndClamps(stability: Double, expected: Int) {
        // Act / Assert(目標保持率 0.9 なので、丸める前の間隔は安定度と同じ)
        #expect(fsrs6.interval(desiredRetention: 0.9, stability: stability, maximumInterval: 36500) == expected)
    }

    @Test("ちょうど半分は偶数に丸める(リファレンス実装の Python の round と同じ)", arguments: [
        (2.5, 2),
        (3.5, 4),
        (2.4999, 2),
        (2.5001, 3),
    ])
    func intervalRoundsHalfToEven(stability: Double, expected: Int) {
        #expect(fsrs6.interval(desiredRetention: 0.9, stability: stability, maximumInterval: 36500) == expected)
    }
}

@Suite("FSRSParameters")
struct FSRSParametersTests {
    @Test("目標保持率は 0.80〜0.95 の範囲だけを受け付ける(BDD 6.5)", arguments: [0.79, 0.96])
    func retentionOutOfRangeIsRejected(retention: Double) {
        #expect(throws: FSRSError.retentionOutOfRange(retention)) {
            try FSRSParameters(desiredRetention: retention)
        }
    }

    @Test("範囲の両端は受け付ける", arguments: [0.80, 0.95])
    func retentionBoundsAreAccepted(retention: Double) throws {
        #expect(try FSRSParameters(desiredRetention: retention).desiredRetention == retention)
    }

    @Test("重みの個数が違えばエラー(FSRS-6 は 21 個)")
    func weightCountIsValidated() {
        #expect(throws: FSRSError.invalidWeightCount(19)) {
            try FSRSParameters(w: Array(repeating: 1, count: 19))
        }
    }

    @Test("既定値はテストベクタ(py-fsrs の既定値)と一致する")
    func defaultsMatchVectors() throws {
        // Arrange
        let vectors = try VectorFile.load()
        // Act
        let defaults = try FSRSParameters()
        // Assert
        #expect(defaults == (try vectors.makeParameters()))
    }
}

@Suite("ElapsedDays")
struct ElapsedDaysTests {
    private let base = Date(timeIntervalSince1970: 1_767_258_000)  // 2026-01-01T09:00:00Z

    @Test("整数の日数は切り捨てる(py-fsrs の timedelta.days と同じ)", arguments: [
        (0.0, 0),
        (23.0, 0),
        (24.0, 1),
        (47.9, 1),
        (-1.0, -1),
    ] as [(Double, Int)])
    func wholeDaysFloor(hours: Double, expected: Int) {
        #expect(ElapsedDays.whole(from: base, to: base.addingTimeInterval(hours * 3600)) == expected)
    }

    @Test("小数の日数")
    func fractionalDays() {
        #expect(ElapsedDays.fractional(from: base, to: base.addingTimeInterval(36 * 3600)) == 1.5)
    }
}
