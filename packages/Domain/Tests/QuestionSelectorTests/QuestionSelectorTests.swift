import Foundation
import Testing
import DomainModels
import DomainTestSupport
@testable import QuestionSelector

@Suite("QuestionSelector")
struct QuestionSelectorTests {
    private let now = Date(timeIntervalSince1970: 1_793_491_200)
    private static let strategies: [SelectionStrategy] = [.random, .weaknessFirst(domainScores: [1: 0.2, 2: 0.9])]

    private func summary(
        _ id: String, domain: Int = 1, subObjective: String = "1.1", caseStudy: CaseStudyID? = nil, difficulty: Int = 3
    ) -> QuestionSummary {
        QuestionSummary(id: id, domain: domain, subObjective: subObjective, caseStudy: caseStudy, difficulty: difficulty, kind: .single)
    }

    /// ID が Q-00, Q-01, … の問題を `count` 問(ドメインは 1 と 2 を交互に)
    private func candidates(_ count: Int) -> [QuestionSummary] {
        (0..<count).map { summary(String(format: "Q-%02d", $0), domain: $0 % 2 + 1) }
    }

    private func hoursAgo(_ hours: Double) -> Date { now.addingTimeInterval(-hours * 3600) }

    private func select(
        _ candidates: [QuestionSummary], history: PracticeHistory = PracticeHistory(),
        criteria: PracticeCriteria = PracticeCriteria(), seed: UInt64 = 1
    ) -> [String] {
        var rng = SeededGenerator(seed: seed)
        return QuestionSelector().select(from: candidates, history: history, criteria: criteria, now: now, using: &rng)
    }

    // MARK: - 絞り込み

    @Test("ドメインで絞り込む(同じ項目の中は OR)")
    func filtersByDomain() {
        // Arrange
        let all = (1...4).flatMap { domain in (0..<3).map { summary("Q-\(domain)-\($0)", domain: domain) } }
        // Act
        let result = select(all, criteria: PracticeCriteria(domains: [1, 3], count: .all))
        // Assert
        #expect(Set(result) == ["Q-1-0", "Q-1-1", "Q-1-2", "Q-3-0", "Q-3-1", "Q-3-2"])
    }

    @Test("サブ項目とケースの両方を満たす問題だけ(異なる項目どうしは AND)")
    func filtersBySubObjectiveAndCase() {
        // Arrange
        let all = [
            summary("A", subObjective: "1.1", caseStudy: "case-a"),
            summary("B", subObjective: "1.1", caseStudy: nil),
            summary("C", subObjective: "1.2", caseStudy: "case-a"),
            summary("D", subObjective: "1.1", caseStudy: "case-b"),
        ]
        // Act
        let result = select(all, criteria: PracticeCriteria(subObjectives: ["1.1"], caseStudies: ["case-a"], count: .all))
        // Assert
        #expect(result == ["A"])
    }

    @Test("難易度の範囲で絞り込む")
    func filtersByDifficulty() {
        // Arrange
        let all = (1...5).map { summary("D\($0)", difficulty: $0) }
        // Act
        let result = select(all, criteria: PracticeCriteria(difficulty: 2...3, count: .all))
        // Assert
        #expect(Set(result) == ["D2", "D3"])
    }

    @Test("間違えた問題のみ: 直近の結果が不正解の問題")
    func wrongOnly() {
        // Arrange
        let history = PracticeHistory(lastResult: ["Q-00": false, "Q-01": false, "Q-02": true])
        // Act
        let result = select(candidates(5), history: history, criteria: PracticeCriteria(scope: .wrongOnly, count: .all))
        // Assert
        #expect(Set(result) == ["Q-00", "Q-01"])
    }

    @Test("未解答のみ: 解答履歴のない問題")
    func unansweredOnly() {
        // Arrange
        let history = PracticeHistory(lastResult: ["Q-00": false, "Q-01": true, "Q-02": true])
        // Act
        let result = select(candidates(5), history: history, criteria: PracticeCriteria(scope: .unanswered, count: .all))
        // Assert
        #expect(Set(result) == ["Q-03", "Q-04"])
    }

    @Test("フラグ付きのみ")
    func flaggedOnly() {
        // Arrange
        let history = PracticeHistory(flagged: ["Q-01", "Q-04"])
        // Act
        let result = select(candidates(5), history: history, criteria: PracticeCriteria(scope: .flagged, count: .all))
        // Assert
        #expect(Set(result) == ["Q-01", "Q-04"])
    }

    @Test("条件に合う問題がなければ空の配列(エラーにしない)")
    func emptyResult() {
        // Act
        let result = select(candidates(5), criteria: PracticeCriteria(domains: [9]))
        // Assert
        #expect(result.isEmpty)
    }

    // MARK: - 件数

    @Test("指定数だけ選ぶ", arguments: [(PracticeCount.fixed(5), 5), (.fixed(10), 10), (.fixed(20), 20), (.all, 30)])
    func countLimits(count: PracticeCount, expected: Int) {
        // Act
        let result = select(candidates(30), criteria: PracticeCriteria(count: count))
        // Assert
        #expect(result.count == expected)
    }

    @Test("指定数が候補より多ければ、候補をすべて返す")
    func countExceedsCandidates() {
        // Act
        let result = select(candidates(3), criteria: PracticeCriteria(count: .fixed(10)))
        // Assert
        #expect(result.count == 3)
    }

    @Test("どの seed でも重複がない", arguments: 0..<100)
    func noDuplicates(seed: UInt64) {
        for strategy in Self.strategies {
            // Act
            let result = select(candidates(30), criteria: PracticeCriteria(count: .fixed(10), strategy: strategy), seed: seed)
            // Assert
            #expect(Set(result).count == 10)
        }
    }

    // MARK: - 直近に出題した問題

    @Test("fresh だけで足りれば、直近 24 時間に出題した問題を含めない", arguments: strategies)
    func excludesRecentWhenEnough(strategy: SelectionStrategy) {
        // Arrange
        let recent = ["Q-00", "Q-03", "Q-07", "Q-12", "Q-19"]
        let history = PracticeHistory(lastServedAt: Dictionary(uniqueKeysWithValues: recent.map { ($0, hoursAgo(1)) }))
        // Act
        let result = select(candidates(20), history: history, criteria: PracticeCriteria(count: .fixed(10), strategy: strategy))
        // Assert
        #expect(result.count == 10)
        #expect(Set(result).isDisjoint(with: recent))
    }

    @Test("fresh が足りなければ、すべての fresh に recent の古い順を補う")
    func fillsFromOldestRecent() {
        // Arrange: Q-00〜Q-05 が recent(Q-00 が最も新しい)
        let history = PracticeHistory(lastServedAt: Dictionary(uniqueKeysWithValues: (0..<6).map {
            (String(format: "Q-%02d", $0), hoursAgo(Double($0 + 1)))
        }))
        // Act
        let result = select(candidates(10), history: history, criteria: PracticeCriteria(count: .fixed(8)))
        // Assert
        #expect(Set(result.prefix(4)) == ["Q-06", "Q-07", "Q-08", "Q-09"])
        #expect(Array(result.suffix(4)) == ["Q-05", "Q-04", "Q-03", "Q-02"])
    }

    @Test("ちょうど 24 時間前に出題した問題は fresh")
    func servedExactlyAtBoundaryIsFresh() {
        // Arrange
        let history = PracticeHistory(lastServedAt: ["Q-00": hoursAgo(24), "Q-01": hoursAgo(23)])
        // Act
        let result = select(candidates(2), history: history, criteria: PracticeCriteria(count: .fixed(1)))
        // Assert
        #expect(result == ["Q-00"])
    }

    // MARK: - 決定論

    @Test("候補の順序によらず、同じ seed なら同じ結果", arguments: strategies)
    func inputOrderDoesNotMatter(strategy: SelectionStrategy) {
        // Arrange
        let criteria = PracticeCriteria(count: .fixed(10), strategy: strategy)
        // Act
        let forward = select(candidates(30), criteria: criteria, seed: 42)
        let reversed = select(candidates(30).reversed(), criteria: criteria, seed: 42)
        // Assert
        #expect(forward == reversed)
    }

    // MARK: - 弱点優先

    /// ドメイン1とドメイン2の問題を1問ずつ置き、1 問の抽出を 10,000 回くり返した出現回数
    private func drawCounts(domainScores: [Int: Double]) -> [Int: Int] {
        let all = [summary("A", domain: 1), summary("B", domain: 2)]
        let criteria = PracticeCriteria(count: .fixed(1), strategy: .weaknessFirst(domainScores: domainScores))
        var rng = SeededGenerator(seed: 2026)
        var counts: [Int: Int] = [:]
        for _ in 0..<10_000 {
            let picked = QuestionSelector().select(from: all, history: PracticeHistory(), criteria: criteria, now: now, using: &rng)
            for id in picked { counts[id == "A" ? 1 : 2, default: 0] += 1 }
        }
        return counts
    }

    @Test("弱点優先: score の低いドメインの問題が多く出る")
    func weaknessFirstPrefersWeakDomain() {
        // Act
        let counts = drawCounts(domainScores: [1: 0.2, 2: 0.9])
        // Assert
        #expect(counts[1, default: 0] > counts[2, default: 0])
        #expect(counts[1, default: 0] + counts[2, default: 0] == 10_000)
    }

    @Test("弱点優先: score が 1 のドメインの問題も出る(minimumWeight)")
    func weaknessFirstStillPicksStrongDomain() {
        // Act
        let counts = drawCounts(domainScores: [1: 0.2, 2: 1.0])
        // Assert
        #expect(counts[2, default: 0] > 0)
    }

    @Test("重みは (1 − score_d) × 未解答ボーナス × 誤答ボーナス", arguments: [
        (nil as Bool?, 0.5 * 1.5), (false, 0.5 * 2.0), (true, 0.5),
    ])
    func weightIncludesBonuses(lastResult: Bool?, expected: Double) {
        // Arrange
        var history = PracticeHistory()
        history.lastResult["Q"] = lastResult
        // Act
        let weight = QuestionSelector().weight(of: summary("Q"), history: history, domainScores: [1: 0.5])
        // Assert
        #expect(approximatelyEqual(weight, expected))
    }

    @Test("score がないドメインは score 0(最も弱い)として扱う")
    func missingDomainScoreIsWeakest() {
        // Act
        let weight = QuestionSelector().weight(
            of: summary("Q", domain: 3), history: PracticeHistory(lastResult: ["Q": true]), domainScores: [1: 0.5]
        )
        // Assert
        #expect(weight == 1)
    }

    @Test("パックの索引の1件から要約を作れる(revision と examSets は使わない)", arguments: [
        CaseStudyID?.some("ehr"), nil,
    ])
    func summaryFromIndexEntry(caseStudy: CaseStudyID?) {
        // Arrange
        let entry = QuestionIndexEntry(
            id: "Q-3.2-0147", revision: 2, domain: 3, subObjective: "3.2", caseStudy: caseStudy, difficulty: 4,
            kind: .multiple, examSets: [1]
        )
        // Act
        let summary = QuestionSummary(entry)
        // Assert
        #expect(summary == QuestionSummary(
            id: "Q-3.2-0147", domain: 3, subObjective: "3.2", caseStudy: caseStudy, difficulty: 4, kind: .multiple
        ))
    }
}
