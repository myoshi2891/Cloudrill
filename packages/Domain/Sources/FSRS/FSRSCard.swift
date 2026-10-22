import Foundation

/// 復習の評価(BDD 6.5)
public enum Rating: Int, Codable, Sendable, CaseIterable {
    case again = 1, hard, good, easy
}

/// カードの段階。リファレンス実装(py-fsrs 6)には new がない(新規カードは learning の step 0 から始まる)が、
/// アプリでは未学習のカードを区別するために持つ。
public enum CardPhase: String, Codable, Sendable {
    case new, learning, review, relearning
}

public struct FSRSCard: Codable, Hashable, Sendable {
    public var phase: CardPhase
    public var stability: Double
    public var difficulty: Double
    public var due: Date
    public var reps: Int
    public var lapses: Int
    public var lastReview: Date?
    /// 学習ステップの位置。review の段階では nil
    public var step: Int?

    public static func new(at now: Date) -> FSRSCard {
        FSRSCard(phase: .new, stability: 0, difficulty: 0, due: now, reps: 0, lapses: 0, lastReview: nil, step: nil)
    }
}

public struct ReviewOutcome: Hashable, Sendable {
    public var card: FSRSCard
    public var elapsedDays: Double
    public var rating: Rating
    public var reviewedAt: Date
}
