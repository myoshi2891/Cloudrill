/// 重み `w` の添字に名前を付ける(式を読みやすくするため)。添字の意味は FSRS-6(py-fsrs 6.3.2)に従う。
/// w[20](忘却曲線の減衰)は ForgettingCurve が使う。
extension FSRSParameters {
    /// 初回の評価での安定度(w[0]〜w[3])
    func initialStability(for rating: Rating) -> Double {
        w[rating.rawValue - 1]
    }

    /// 初回の難易度の基準値(w[4])
    var initialDifficultyBase: Double { w[4] }

    /// 初回の難易度の、評価による変化の大きさ(w[5])
    var initialDifficultyScale: Double { w[5] }

    /// 評価による難易度の変化の大きさ(w[6])
    var difficultyDelta: Double { w[6] }

    /// 難易度の、Easy の初期値への平均回帰の重み(w[7])
    var difficultyMeanReversion: Double { w[7] }

    /// 想起時の安定度の増加: 全体の係数(w[8]、e の指数)
    var recallStabilityScale: Double { w[8] }

    /// 想起時の安定度の増加: 安定度が大きいほど増えにくくする指数(w[9])
    var recallStabilityDecay: Double { w[9] }

    /// 想起時の安定度の増加: 記憶保持率が低いほど大きく増やす係数(w[10])
    var recallRetrievabilityGain: Double { w[10] }

    /// 忘却時の安定度: 全体の係数(w[11])
    var forgetStabilityScale: Double { w[11] }

    /// 忘却時の安定度: 難易度の指数(w[12])
    var forgetDifficultyExponent: Double { w[12] }

    /// 忘却時の安定度: 前の安定度の指数(w[13])
    var forgetStabilityExponent: Double { w[13] }

    /// 忘却時の安定度: 記憶保持率の係数(w[14])
    var forgetRetrievabilityGain: Double { w[14] }

    /// 想起時の Hard の減点(w[15])
    var hardPenalty: Double { w[15] }

    /// 想起時の Easy の加点(w[16])
    var easyBonus: Double { w[16] }

    /// 短期(同じ日)の安定度: 評価の係数(w[17])
    var shortTermRatingScale: Double { w[17] }

    /// 短期(同じ日)の安定度: 評価のずれ(w[18])
    var shortTermRatingOffset: Double { w[18] }

    /// 短期(同じ日)の安定度: 安定度が大きいほど増えにくくする指数(w[19])
    var shortTermStabilityDecay: Double { w[19] }
}
