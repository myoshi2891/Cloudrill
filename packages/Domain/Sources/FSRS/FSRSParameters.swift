public enum FSRSError: Error, Equatable, Sendable {
    /// 目標保持率が設定できる範囲の外(P1-S08b で確認を実装する)
    case retentionOutOfRange(Double)
}

/// スケジューラのパラメータ。値はテストベクタ(py-fsrs の既定値)に合わせる。
public struct FSRSParameters: Hashable, Sendable {
    public var w: [Double]
    public var desiredRetention: Double
    public var learningSteps: [Duration]
    public var relearningSteps: [Duration]
    /// review の段階の間隔の上限(日)
    public var maximumInterval: Int

    public init(
        w: [Double], desiredRetention: Double, learningSteps: [Duration], relearningSteps: [Duration], maximumInterval: Int
    ) throws(FSRSError) {
        self.w = w
        self.desiredRetention = desiredRetention
        self.learningSteps = learningSteps
        self.relearningSteps = relearningSteps
        self.maximumInterval = maximumInterval
    }
}
