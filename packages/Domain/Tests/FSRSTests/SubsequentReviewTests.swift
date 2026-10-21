import Foundation
import Testing
@testable import FSRS

@Suite("FSRS: 2回目以降の評価")
struct SubsequentReviewTests {
    private let now = Date(timeIntervalSince1970: 1_767_258_000)  // 2026-01-01T09:00:00Z

    private func scheduler() throws -> FSRSScheduler {
        FSRSScheduler(parameters: try FSRSParameters())
    }

    /// review の段階のカード(新規カードに Easy を付けたもの)
    private func reviewCard(_ scheduler: FSRSScheduler) -> FSRSCard {
        scheduler.review(.new(at: now), rating: .easy, at: now).card
    }

    @Test("review の段階で Again を付けると、忘却の回数が増えて relearning に移る")
    func againIncrementsLapses() throws {
        // Arrange
        let scheduler = try scheduler()
        let card = reviewCard(scheduler)
        // Act
        let next = scheduler.review(card, rating: .again, at: card.due).card
        // Assert
        #expect(next.lapses == card.lapses + 1)
        #expect(next.phase == .relearning)
        #expect(next.step == 0)
        #expect(next.due == card.due.addingTimeInterval(600))
    }

    @Test("relearning の段階の Again では、忘却の回数を増やさない")
    func againInRelearningDoesNotIncrementLapses() throws {
        // Arrange
        let scheduler = try scheduler()
        let relearning = scheduler.review(reviewCard(scheduler), rating: .again, at: reviewCard(scheduler).due).card
        // Act
        let next = scheduler.review(relearning, rating: .again, at: relearning.due).card
        // Assert
        #expect(next.lapses == relearning.lapses)
        #expect(next.phase == .relearning)
    }

    @Test("期限ちょうどの Good で安定度が増える")
    func goodIncreasesStability() throws {
        // Arrange
        let scheduler = try scheduler()
        let card = reviewCard(scheduler)
        // Act
        let next = scheduler.review(card, rating: .good, at: card.due).card
        // Assert
        #expect(next.stability > card.stability)
        #expect(next.phase == .review)
        #expect(next.reps == card.reps + 1)
    }

    @Test("同じ状態のカードでは、Again のほうが Easy より難易度が大きい")
    func difficultyMovesWithRating() throws {
        // Arrange
        let scheduler = try scheduler()
        let card = reviewCard(scheduler)
        // Act
        let again = scheduler.review(card, rating: .again, at: card.due).card
        let easy = scheduler.review(card, rating: .easy, at: card.due).card
        // Assert
        #expect(again.difficulty > easy.difficulty)
    }

    @Test("期限より遅い Good は、期限ちょうどの Good より安定度が大きい(忘れかけた状態での想起は記憶を強くする)")
    func lateReviewUsesElapsedDays() throws {
        // Arrange
        let scheduler = try scheduler()
        let card = reviewCard(scheduler)
        // Act
        let onTime = scheduler.review(card, rating: .good, at: card.due).card
        let late = scheduler.review(card, rating: .good, at: card.due.addingTimeInterval(10 * 86_400)).card
        // Assert
        #expect(late.stability > onTime.stability)
    }

    @Test("24 時間未満の再評価は短期の安定度の式で更新する(テストベクタの same-day-review と一致)")
    func sameDayReview() throws {
        // Arrange
        let vectors = try VectorFile.load()
        let scheduler = FSRSScheduler(parameters: try vectors.makeParameters())
        let vectorCase = try #require(vectors.cases.first { $0.name == "same-day-review" })
        // Act / Assert
        try replay(vectorCase, with: scheduler)
    }

    @Test("経過日数を記録する(前回の評価からの小数の日数)")
    func recordsElapsedDays() throws {
        // Arrange
        let scheduler = try scheduler()
        let card = reviewCard(scheduler)
        // Act
        let outcome = scheduler.review(card, rating: .good, at: now.addingTimeInterval(36 * 3600))
        // Assert
        #expect(outcome.elapsedDays == 1.5)
    }
}
