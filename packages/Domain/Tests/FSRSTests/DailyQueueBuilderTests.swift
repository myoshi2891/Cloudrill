import Foundation
import Testing
@testable import FSRS

@Suite("DailyQueueBuilder")
struct DailyQueueBuilderTests {
    /// 2026-11-01 09:00(Asia/Tokyo)= 2026-11-01T00:00:00Z
    private let now = Date(timeIntervalSince1970: 1_793_491_200)
    private let limits = DailyLimits(newCards: 10, reviews: 100)

    private func builder() throws -> DailyQueueBuilder {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = try #require(TimeZone(identifier: "Asia/Tokyo"))
        return DailyQueueBuilder(calendar: calendar)
    }

    /// 現在からの時間(時)を期限に持つ review の段階のカード
    private func due(_ id: String, hours: Double, phase: CardPhase = .review) -> ScheduledCard {
        let card = FSRSCard(
            phase: phase, stability: 3, difficulty: 5, due: now.addingTimeInterval(hours * 3600),
            reps: 1, lapses: 0, lastReview: now.addingTimeInterval(-86_400), step: nil
        )
        return ScheduledCard(id: id, card: card)
    }

    private func build(
        _ candidates: [ScheduledCard], newCardIDs: [String] = [], limits: DailyLimits? = nil,
        introducedToday: Int = 0, reviewedToday: Int = 0
    ) throws -> DailyQueue {
        try builder().build(
            reviewCandidates: candidates, newCardIDs: newCardIDs, limits: limits ?? self.limits,
            introducedToday: introducedToday, reviewedToday: reviewedToday, now: now
        )
    }

    @Test("復習を先に、新規を後に並べる")
    func reviewsBeforeNew() throws {
        // Act
        let queue = try build(
            [due("R1", hours: -48), due("R2", hours: -24), due("R3", hours: -1)],
            newCardIDs: ["N1", "N2", "N3", "N4", "N5"]
        )
        // Assert
        #expect(queue.reviewCardIDs == ["R1", "R2", "R3"])
        #expect(queue.newCardIDs == ["N1", "N2", "N3", "N4", "N5"])
        #expect(queue.cardIDs == ["R1", "R2", "R3", "N1", "N2", "N3", "N4", "N5"])
    }

    @Test("復習は上限まで")
    func reviewLimit() throws {
        // Act
        let queue = try build((0..<150).map { due("R\($0)", hours: -Double($0 + 1)) })
        // Assert
        #expect(queue.reviewCardIDs.count == 100)
    }

    @Test("新規の上限から、今日すでに学習した枚数を引く")
    func newLimitConsidersToday() throws {
        // Act
        let queue = try build(
            [], newCardIDs: (0..<30).map { "N\($0)" }, limits: DailyLimits(newCards: 20, reviews: 100), introducedToday: 15
        )
        // Assert
        #expect(queue.newCardIDs == ["N0", "N1", "N2", "N3", "N4"])
    }

    @Test("復習の上限から、今日すでに復習した枚数を引く(上限を超えていれば 0)", arguments: [(90, 10), (120, 0)])
    func reviewLimitConsidersToday(reviewedToday: Int, expected: Int) throws {
        // Act
        let queue = try build((0..<50).map { due("R\($0)", hours: -1) }, reviewedToday: reviewedToday)
        // Assert
        #expect(queue.reviewCardIDs.count == expected)
    }

    @Test("復習は期限の古い順。同じ期限なら候補の順を保つ")
    func dueOrder() throws {
        // Act
        let queue = try build([due("C", hours: -1), due("A", hours: -30), due("B2", hours: -5), due("B1", hours: -5)])
        // Assert
        #expect(queue.reviewCardIDs == ["A", "B2", "B1", "C"])
    }

    @Test("今日の終わり(端末のタイムゾーンの 24:00)までが期限のカードは、今日のキューに含める")
    func dueUntilEndOfLocalDay() throws {
        // Act(9:00 から 14 時間後 = 23:00)
        let queue = try build([due("R1", hours: 14)])
        // Assert
        #expect(queue.reviewCardIDs == ["R1"])
    }

    @Test("期限が明日のカードは含めない(明日の 0:30)")
    func notDueTomorrow() throws {
        // Act(9:00 から 15.5 時間後 = 翌日 0:30)
        let queue = try build([due("R1", hours: 15.5)])
        // Assert
        #expect(queue.reviewCardIDs.isEmpty)
    }

    @Test("learning・relearning の段階のカードも、期限が今日なら復習に含める。未学習のカードは含めない")
    func phasesInReviewCandidates() throws {
        // Act
        let queue = try build([
            due("L", hours: 0.2, phase: .learning),
            due("RL", hours: 0.1, phase: .relearning),
            due("NEW", hours: -1, phase: .new),
        ])
        // Assert
        #expect(queue.reviewCardIDs == ["RL", "L"])
    }

    @Test("新規カードはコンテンツ側の順のまま")
    func newCardOrderIsStable() throws {
        // Act
        let queue = try build([], newCardIDs: ["Z", "A", "M"])
        // Assert
        #expect(queue.newCardIDs == ["Z", "A", "M"])
    }

    @Test("負の上限は 0 として扱う")
    func negativeLimitsAreZero() throws {
        // Act
        let queue = try build([due("R1", hours: -1)], newCardIDs: ["N1"], limits: DailyLimits(newCards: -1, reviews: -1))
        // Assert
        #expect(queue.cardIDs.isEmpty)
    }
}
