public enum ReadinessError: Error, Equatable, Sendable {
    /// 正答率と記憶保持率の重みの合計が 1 でない
    case weightsMustSumToOne(accuracy: Double, retention: Double)
    /// 解答の重みの半減期(日)が 0 以下
    case nonPositiveHalfLife(Double)
    /// 網羅度が 1 になるユニークな問題数が 0 以下
    case nonPositiveCoverageTarget(Int)
}

/// 合格準備度の計算のパラメータ。既定値は BDD 6.6 の値
public struct ReadinessParameters: Hashable, Sendable {
    /// `score_d` での正答率の重み
    public var accuracyWeight: Double
    /// `score_d` での記憶保持率の重み
    public var retentionWeight: Double
    /// 解答の重み `0.5^(t / halfLifeDays)` の半減期(日)
    public var halfLifeDays: Double
    /// 網羅度 `cov_d` が 1 になる、ドメインごとのユニークな問題数
    public var coverageTarget: Int
    /// 準備度を算出するのに必要な、ユニークな問題数(これ未満は「データ収集中」)
    public var minimumUniqueQuestions: Int

    public init(
        accuracyWeight: Double = 0.7,
        retentionWeight: Double = 0.3,
        halfLifeDays: Double = 14,
        coverageTarget: Int = 20,
        minimumUniqueQuestions: Int = 30
    ) throws(ReadinessError) {
        guard abs(accuracyWeight + retentionWeight - 1) <= 1e-9 else {
            throw .weightsMustSumToOne(accuracy: accuracyWeight, retention: retentionWeight)
        }
        guard halfLifeDays > 0 else { throw .nonPositiveHalfLife(halfLifeDays) }
        guard coverageTarget > 0 else { throw .nonPositiveCoverageTarget(coverageTarget) }
        self.accuracyWeight = accuracyWeight
        self.retentionWeight = retentionWeight
        self.halfLifeDays = halfLifeDays
        self.coverageTarget = coverageTarget
        self.minimumUniqueQuestions = minimumUniqueQuestions
    }
}
