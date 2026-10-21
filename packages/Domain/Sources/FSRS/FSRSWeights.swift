/// 重み `w` の添字に名前を付ける(式を読みやすくするため)。添字の意味は FSRS-6(py-fsrs 6.3.2)に従う。
/// 2回目以降の評価で使う重み(w[6] 以降)は P1-S08d で追加する。
extension FSRSParameters {
    /// 初回の評価での安定度(w[0]〜w[3])
    func initialStability(for rating: Rating) -> Double {
        w[rating.rawValue - 1]
    }

    /// 初回の難易度の基準値(w[4])
    var initialDifficultyBase: Double { w[4] }

    /// 初回の難易度の、評価による変化の大きさ(w[5])
    var initialDifficultyScale: Double { w[5] }
}
