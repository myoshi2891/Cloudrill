import Foundation

/// FSRS のスケジューラ(BDD 6.5)。
/// 仮の実装: P1-S08a では、テストベクタの照合を Red にするため、カードを変えずに返す。P1-S08b〜d で実装する。
public struct FSRSScheduler: Sendable {
    public let parameters: FSRSParameters

    public init(parameters: FSRSParameters) {
        self.parameters = parameters
    }

    public func review(_ card: FSRSCard, rating: Rating, at now: Date) -> ReviewOutcome {
        ReviewOutcome(card: card, elapsedDays: 0, rating: rating, reviewedAt: now)
    }

    public func retrievability(of card: FSRSCard, at now: Date) -> Double {
        0
    }
}
