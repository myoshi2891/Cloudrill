public enum FSRSError: Error, Equatable, Sendable {
    /// 目標保持率が設定できる範囲(`FSRSParameters.retentionRange`)の外
    case retentionOutOfRange(Double)
    /// 重みの個数が FSRS-6 の個数(`FSRSParameters.weightCount`)と異なる
    case invalidWeightCount(Int)
}

/// スケジューラのパラメータ。既定値はリファレンス実装(py-fsrs 6.3.2、FSRS-6)の既定値と同じ
/// (FSRSParametersTests.defaultsMatchVectors で、テストベクタと一致することを確かめる)。
public struct FSRSParameters: Hashable, Sendable {
    public static let weightCount = 21
    /// 利用者が設定できる目標保持率(BDD 6.5)
    public static let retentionRange: ClosedRange<Double> = 0.80...0.95

    /// py-fsrs 6.3.2 の DEFAULT_PARAMETERS(w[20] は忘却曲線の減衰)
    public static let defaultWeights: [Double] = [
        0.212, 1.2931, 2.3065, 8.2956, 6.4133, 0.8334, 3.0194, 0.001, 1.8722, 0.1666, 0.796,
        1.4835, 0.0614, 0.2629, 1.6483, 0.6014, 1.8729, 0.5425, 0.0912, 0.0658, 0.1542,
    ]

    // 初期化での検証を後から崩せないよう、検証する値は外から変更させない
    public private(set) var w: [Double]
    public private(set) var desiredRetention: Double
    public var learningSteps: [Duration]
    public var relearningSteps: [Duration]
    /// review の段階の間隔の上限(日)
    public var maximumInterval: Int

    public init(
        w: [Double] = defaultWeights,
        desiredRetention: Double = 0.9,
        learningSteps: [Duration] = [.seconds(60), .seconds(600)],
        relearningSteps: [Duration] = [.seconds(600)],
        maximumInterval: Int = 36500
    ) throws(FSRSError) {
        guard w.count == Self.weightCount else { throw .invalidWeightCount(w.count) }
        guard Self.retentionRange.contains(desiredRetention) else { throw .retentionOutOfRange(desiredRetention) }
        self.w = w
        self.desiredRetention = desiredRetention
        self.learningSteps = learningSteps
        self.relearningSteps = relearningSteps
        self.maximumInterval = maximumInterval
    }
}
