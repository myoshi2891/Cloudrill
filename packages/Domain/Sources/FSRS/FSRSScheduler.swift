import Foundation

/// FSRS のスケジューラ(BDD 6.5)。リファレンス実装(py-fsrs 6.3.2、FSRS-6)の結果と一致させる(AC-08)。
/// 式の正しさはテストベクタ(FSRSVectorTests)で判断する。間隔のゆらぎ(fuzz)は使わない(結果を決定論にするため)。
public struct FSRSScheduler: Sendable {
    public let parameters: FSRSParameters
    private let curve: ForgettingCurve

    static let stabilityMin = 0.001
    static let difficultyRange: ClosedRange<Double> = 1...10

    public init(parameters: FSRSParameters) {
        self.parameters = parameters
        curve = ForgettingCurve(parameters: parameters)
    }

    public func review(_ card: FSRSCard, rating: Rating, at now: Date) -> ReviewOutcome {
        let elapsedDays = card.lastReview.map { ElapsedDays.fractional(from: $0, to: now) } ?? 0
        var next = switch card.phase {
        case .new: reviewNew(card, rating: rating, at: now)
        case .learning: reviewLearning(card, rating: rating, at: now)
        case .review: reviewReview(card, rating: rating, at: now)
        case .relearning: reviewRelearning(card, rating: rating, at: now)
        }
        next.reps = card.reps + 1
        next.lastReview = now
        return ReviewOutcome(card: next, elapsedDays: elapsedDays, rating: rating, reviewedAt: now)
    }

    /// 最後の評価からの経過日数(切り捨ての整数日。リファレンス実装と同じ)での記憶保持率。未学習なら 0
    public func retrievability(of card: FSRSCard, at now: Date) -> Double {
        guard let lastReview = card.lastReview, card.phase != .new else { return 0 }
        let days = max(0, ElapsedDays.whole(from: lastReview, to: now))
        return curve.retrievability(elapsedDays: Double(days), stability: card.stability)
    }

    // MARK: - 段階ごとの評価

    /// 未学習のカード。リファレンス実装では learning の step 0 として扱われる
    private func reviewNew(_ card: FSRSCard, rating: Rating, at now: Date) -> FSRSCard {
        var next = card
        next.stability = clampStability(parameters.initialStability(for: rating))
        next.difficulty = clampDifficulty(initialDifficulty(for: rating))
        next.phase = .learning
        next.step = 0
        return scheduleStep(next, rating: rating, steps: parameters.learningSteps, at: now)
    }

    private func reviewLearning(_ card: FSRSCard, rating: Rating, at now: Date) -> FSRSCard {
        let next = updateMemory(card, rating: rating, at: now)
        return scheduleStep(next, rating: rating, steps: parameters.learningSteps, at: now)
    }

    private func reviewRelearning(_ card: FSRSCard, rating: Rating, at now: Date) -> FSRSCard {
        let next = updateMemory(card, rating: rating, at: now)
        return scheduleStep(next, rating: rating, steps: parameters.relearningSteps, at: now)
    }

    private func reviewReview(_ card: FSRSCard, rating: Rating, at now: Date) -> FSRSCard {
        var next = updateMemory(card, rating: rating, at: now)
        guard rating == .again else { return graduate(next, at: now) }
        // 忘却。忘却の回数は review の段階での Again だけを数える(アプリ独自の値。リファレンス実装にはない)
        next.lapses = card.lapses + 1
        guard let firstStep = parameters.relearningSteps.first else { return graduate(next, at: now) }
        next.phase = .relearning
        next.step = 0
        next.due = now.addingTimeInterval(firstStep.timeInterval)
        return next
    }

    /// 安定度と難易度を更新する。前回から 24 時間未満なら短期の式、それ以外は想起時・忘却時の式を使う
    private func updateMemory(_ card: FSRSCard, rating: Rating, at now: Date) -> FSRSCard {
        var next = card
        let isSameDay = card.lastReview.map { ElapsedDays.whole(from: $0, to: now) < 1 } ?? false
        if isSameDay {
            next.stability = shortTermStability(card.stability, rating: rating)
        } else {
            let retrievability = retrievability(of: card, at: now)
            next.stability = rating == .again
                ? forgetStability(difficulty: card.difficulty, stability: card.stability, retrievability: retrievability)
                : recallStability(difficulty: card.difficulty, stability: card.stability, retrievability: retrievability, rating: rating)
        }
        next.difficulty = nextDifficulty(card.difficulty, rating: rating)
        return next
    }

    // MARK: - 期限

    /// learning・relearning の段階の期限。ステップを使い切るか Easy なら review に移る
    private func scheduleStep(_ card: FSRSCard, rating: Rating, steps: [Duration], at now: Date) -> FSRSCard {
        var next = card
        let step = card.step ?? 0
        if steps.isEmpty || (step >= steps.count && rating != .again) {
            return graduate(next, at: now)
        }
        switch rating {
        case .again:
            next.step = 0
            next.due = now.addingTimeInterval(steps[0].timeInterval)
        case .hard:
            // ステップは進めない。最初のステップでは、次のステップとの中間(1つしかなければ 1.5 倍)
            let interval: Duration = switch (step, steps.count) {
            case (0, 1): steps[0] * 1.5
            case (0, _): (steps[0] + steps[1]) / 2
            default: steps[step]
            }
            next.due = now.addingTimeInterval(interval.timeInterval)
        case .good:
            guard step + 1 < steps.count else { return graduate(next, at: now) }
            next.step = step + 1
            next.due = now.addingTimeInterval(steps[step + 1].timeInterval)
        case .easy:
            return graduate(next, at: now)
        }
        return next
    }

    /// review の段階に移し(または留め)、安定度から日単位の間隔を決める
    private func graduate(_ card: FSRSCard, at now: Date) -> FSRSCard {
        var next = card
        next.phase = .review
        next.step = nil
        let days = curve.interval(
            desiredRetention: parameters.desiredRetention,
            stability: card.stability,
            maximumInterval: parameters.maximumInterval
        )
        next.due = now.addingTimeInterval(Double(days) * ElapsedDays.secondsPerDay)
        return next
    }

    // MARK: - 式

    private func initialDifficulty(for rating: Rating) -> Double {
        parameters.initialDifficultyBase - exp(parameters.initialDifficultyScale * Double(rating.rawValue - 1)) + 1
    }

    /// 線形の減衰(10 に近いほど上がりにくい)と、Easy の初期値への平均回帰
    private func nextDifficulty(_ difficulty: Double, rating: Rating) -> Double {
        let delta = -parameters.difficultyDelta * Double(rating.rawValue - 3)
        let damped = difficulty + (10 - difficulty) * delta / 9
        let target = initialDifficulty(for: .easy)  // 丸めない値に回帰させる(リファレンス実装と同じ)
        let reverted = parameters.difficultyMeanReversion * target + (1 - parameters.difficultyMeanReversion) * damped
        return clampDifficulty(reverted)
    }

    /// 想起(Hard・Good・Easy)。記憶保持率が低いときに想起するほど、安定度が大きく増える
    private func recallStability(difficulty: Double, stability: Double, retrievability: Double, rating: Rating) -> Double {
        let hardPenalty = rating == .hard ? parameters.hardPenalty : 1
        let easyBonus = rating == .easy ? parameters.easyBonus : 1
        let increase = exp(parameters.recallStabilityScale)
            * (11 - difficulty)
            * pow(stability, -parameters.recallStabilityDecay)
            * (exp((1 - retrievability) * parameters.recallRetrievabilityGain) - 1)
            * hardPenalty
            * easyBonus
        return clampStability(stability * (1 + increase))
    }

    /// 忘却(Again)。長期の式と短期の式の小さい方
    private func forgetStability(difficulty: Double, stability: Double, retrievability: Double) -> Double {
        let longTerm = parameters.forgetStabilityScale
            * pow(difficulty, -parameters.forgetDifficultyExponent)
            * (pow(stability + 1, parameters.forgetStabilityExponent) - 1)
            * exp((1 - retrievability) * parameters.forgetRetrievabilityGain)
        let shortTerm = stability / exp(parameters.shortTermRatingScale * parameters.shortTermRatingOffset)
        return clampStability(min(longTerm, shortTerm))
    }

    /// 短期(前回から 24 時間未満)。Hard 以上では安定度を下げない
    /// (py-fsrs 6.3.2 は Hard も下限の対象にする。FSRS-6 の説明の「Good 以上」ではなく、リファレンス実装に合わせる)
    private func shortTermStability(_ stability: Double, rating: Rating) -> Double {
        var increase = exp(parameters.shortTermRatingScale * (Double(rating.rawValue) - 3 + parameters.shortTermRatingOffset))
            * pow(stability, -parameters.shortTermStabilityDecay)
        if rating != .again {
            increase = max(increase, 1)
        }
        return clampStability(stability * increase)
    }

    private func clampStability(_ stability: Double) -> Double {
        max(stability, Self.stabilityMin)
    }

    private func clampDifficulty(_ difficulty: Double) -> Double {
        min(max(difficulty, Self.difficultyRange.lowerBound), Self.difficultyRange.upperBound)
    }
}

extension Duration {
    /// 秒の `Double`(FSRS は StudyModels に依存しないので、ここで変換する)
    var timeInterval: TimeInterval {
        let (seconds, attoseconds) = components
        return TimeInterval(seconds) + TimeInterval(attoseconds) / 1e18
    }
}
