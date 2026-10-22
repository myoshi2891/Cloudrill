import Foundation
import Testing
@testable import FSRS

@Suite("FSRS: 初回の評価")
struct InitialReviewTests {
    private let now = Date(timeIntervalSince1970: 1_767_258_000)  // 2026-01-01T09:00:00Z

    private func scheduler() throws -> FSRSScheduler {
        FSRSScheduler(parameters: try FSRSParameters())
    }

    @Test("初回の安定度は評価ごとの重み(w[0]〜w[3])", arguments: zip(Rating.allCases, 0..<4))
    func initialStabilityPerRating(rating: Rating, weightIndex: Int) throws {
        // Arrange
        let scheduler = try scheduler()
        // Act
        let card = scheduler.review(.new(at: now), rating: rating, at: now).card
        // Assert
        #expect(card.stability == FSRSParameters.defaultWeights[weightIndex])
    }

    @Test("初回の難易度は 1〜10 の範囲", arguments: Rating.allCases)
    func initialDifficultyIsClamped(rating: Rating) throws {
        // Act
        let card = try scheduler().review(.new(at: now), rating: rating, at: now).card
        // Assert
        #expect((1.0...10.0).contains(card.difficulty))
    }

    @Test("易しい評価ほど期限が遅い")
    func easierRatingGivesLongerDue() throws {
        // Arrange
        let scheduler = try scheduler()
        // Act
        let dues = Rating.allCases.map { scheduler.review(.new(at: now), rating: $0, at: now).card.due }
        // Assert
        #expect(zip(dues, dues.dropFirst()).allSatisfy { $0 < $1 })
    }

    @Test("学習ステップ: Again は 1 分後、Hard は 5.5 分後(最初の2ステップの平均)、Good は次のステップ、Easy は review", arguments: [
        (Rating.again, CardPhase.learning, 0 as Int?, 60.0),
        (.hard, .learning, 0, 330),
        (.good, .learning, 1, 600),
    ])
    func learningSteps(rating: Rating, phase: CardPhase, step: Int?, seconds: Double) throws {
        // Act
        let card = try scheduler().review(.new(at: now), rating: rating, at: now).card
        // Assert
        #expect(card.phase == phase)
        #expect(card.step == step)
        #expect(card.due.timeIntervalSince(now) == seconds)
    }

    @Test("初回の評価で、回数・最終評価の時刻・経過日数を記録する")
    func recordsReviewFacts() throws {
        // Act
        let outcome = try scheduler().review(.new(at: now), rating: .easy, at: now)
        // Assert
        #expect(outcome.card.phase == .review)
        #expect(outcome.card.step == nil)
        #expect(outcome.card.reps == 1)
        #expect(outcome.card.lapses == 0)
        #expect(outcome.card.lastReview == now)
        #expect(outcome.elapsedDays == 0)
        #expect(outcome.rating == .easy)
        #expect(outcome.reviewedAt == now)
    }

    @Test("未学習のカードの記憶保持率は 0")
    func newCardRetrievabilityIsZero() throws {
        #expect(try scheduler().retrievability(of: .new(at: now), at: now) == 0)
    }

    @Test("テストベクタのうち、評価が1回だけのケースと一致する")
    func vectorsInitialCases() throws {
        // Arrange
        let vectors = try VectorFile.load()
        let scheduler = FSRSScheduler(parameters: try vectors.makeParameters())
        let initialCases = vectors.cases.filter { $0.reviews.count == 1 }
        #expect(initialCases.count == 4)
        // Act / Assert
        for vectorCase in initialCases {
            try replay(vectorCase, with: scheduler)
        }
    }
}
