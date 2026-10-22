import Foundation

/// 忘却曲線 `R(t, S) = (1 + FACTOR × t / S) ^ DECAY` と、その逆関数による間隔。
/// FSRS-5 は DECAY が定数、FSRS-6 は DECAY がパラメータ(`-w[20]`)。FACTOR はどちらも `R(S, S) = 0.9` になるよう決める。
public struct ForgettingCurve: Hashable, Sendable {
    /// 負の値
    public let decay: Double
    public let factor: Double

    public init(decay: Double) {
        self.decay = decay
        factor = pow(0.9, 1 / decay) - 1
    }

    /// FSRS-6: DECAY は w[20]
    public init(parameters: FSRSParameters) {
        self.init(decay: -parameters.w[20])
    }

    /// FSRS-5: DECAY = -0.5(FACTOR = 19/81)
    public static let fsrs5 = ForgettingCurve(decay: -0.5)

    /// 経過日数 t での記憶保持率
    public func retrievability(elapsedDays: Double, stability: Double) -> Double {
        pow(1 + factor * elapsedDays / stability, decay)
    }

    /// 記憶保持率が目標まで下がるまでの日数(丸める前)
    public func rawInterval(desiredRetention: Double, stability: Double) -> Double {
        stability / factor * (pow(desiredRetention, 1 / decay) - 1)
    }

    /// 次の間隔(日)。日単位に丸め、1 日以上・`maximumInterval` 以下にする。
    /// 丸めは偶数への丸め(リファレンス実装の Python の `round` と同じ。2.5 → 2、3.5 → 4)。
    public func interval(desiredRetention: Double, stability: Double, maximumInterval: Int) -> Int {
        let rounded = rawInterval(desiredRetention: desiredRetention, stability: stability).rounded(.toNearestOrEven)
        return min(max(Int(rounded), 1), maximumInterval)
    }
}
