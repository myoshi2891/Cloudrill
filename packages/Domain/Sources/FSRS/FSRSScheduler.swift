import Foundation

/// FSRS のスケジューラ(BDD 6.5)。リファレンス実装(py-fsrs 6.3.2、FSRS-6)の結果と一致させる(AC-08)。
/// 間隔のゆらぎ(fuzz)は使わない(結果を決定論にするため)。
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
        var next: FSRSCard
        switch card.phase {
        case .new:
            next = reviewNew(card, rating: rating, at: now)
        case .learning, .review, .relearning:
            // 2回目以降の評価は P1-S08d で実装する(それまではカードを変えない)
            return ReviewOutcome(card: card, elapsedDays: elapsedDays, rating: rating, reviewedAt: now)
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
        return scheduleLearningStep(next, rating: rating, at: now)
    }

    // MARK: - 期限

    /// learning の段階の期限。ステップを使い切るか Easy なら review に移る
    private func scheduleLearningStep(_ card: FSRSCard, rating: Rating, at now: Date) -> FSRSCard {
        var next = card
        let steps = parameters.learningSteps
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

    /// review の段階に移し、安定度から日単位の間隔を決める
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
