/// 練習の出題選択のパラメータ。ボーナスと最小の重みは BDD 6.7 に値がないため DDD-P1 P1-S10 で決めた(β版のデータで調整する)
public struct SelectionParameters: Hashable, Sendable {
    /// この時間内に出題した問題(recent)は、候補が足りる限り除外する
    public var recentExclusion: Duration
    /// 解答したことがない問題の重みの倍率
    public var unansweredBonus: Double
    /// 直近の解答が不正解の問題の重みの倍率
    public var wrongBonus: Double
    /// `1 − score_d` の下限。score_d = 1 のドメインの問題が二度と出なくなるのを防ぐ
    public var minimumWeight: Double

    /// 重みは正でなければ抽出の鍵が計算できないので、プログラムの誤りとして止める
    public init(
        recentExclusion: Duration = .seconds(86_400),
        unansweredBonus: Double = 1.5,
        wrongBonus: Double = 2.0,
        minimumWeight: Double = 0.05
    ) {
        precondition(recentExclusion >= .zero, "recentExclusion は 0 以上が必要")
        precondition(unansweredBonus > 0 && wrongBonus > 0, "ボーナスは正の値が必要")
        precondition(minimumWeight > 0, "minimumWeight は正の値が必要")
        self.recentExclusion = recentExclusion
        self.unansweredBonus = unansweredBonus
        self.wrongBonus = wrongBonus
        self.minimumWeight = minimumWeight
    }
}
