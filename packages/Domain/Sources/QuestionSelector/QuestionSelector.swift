import Foundation
import StudyModels

/// 練習の出題選択(BDD 6.7)。候補・履歴・条件・乱数の列が同じなら、候補の順序によらず同じ結果になる。
public struct QuestionSelector: Sendable {
    public let parameters: SelectionParameters

    public init(parameters: SelectionParameters = .init()) { self.parameters = parameters }

    /// 選んだ問題の ID。条件に合う問題がなければ空(エラーにしない。画面で「該当する問題がありません」と表示する)
    public func select(
        from candidates: [QuestionSummary],
        history: PracticeHistory,
        criteria: PracticeCriteria,
        now: Date,
        using rng: inout some RandomNumberGenerator
    ) -> [String] {
        // 入力の順序に結果が左右されないよう、問題 ID の昇順にしてから乱数を使う
        let filtered = filter(candidates.sorted { $0.id < $1.id }, criteria: criteria, history: history)
        let count = switch criteria.count {
        case .fixed(let n): min(max(0, n), filtered.count)
        case .all: filtered.count
        }
        let (fresh, recent) = splitByRecency(filtered, history: history, now: now)
        guard fresh.count < count else {
            return draw(count, from: fresh, strategy: criteria.strategy, history: history, using: &rng)
        }
        // fresh だけでは足りないので、すべての fresh に、recent を出題の古い順に補う
        let fill = recent.prefix(count - fresh.count).map(\.id)
        return draw(fresh.count, from: fresh, strategy: criteria.strategy, history: history, using: &rng) + fill
    }

    // MARK: - 手順 2・3: 絞り込み

    func filter(_ candidates: [QuestionSummary], criteria: PracticeCriteria, history: PracticeHistory) -> [QuestionSummary] {
        candidates.filter { matches($0, criteria) && isInScope($0, criteria.scope, history: history) }
    }

    private func matches(_ question: QuestionSummary, _ criteria: PracticeCriteria) -> Bool {
        (criteria.domains.isEmpty || criteria.domains.contains(question.domain))
            && (criteria.subObjectives.isEmpty || criteria.subObjectives.contains(question.subObjective))
            && (criteria.caseStudies.isEmpty || question.caseStudy.map(criteria.caseStudies.contains) == true)
            && (criteria.difficulty.map { $0.contains(question.difficulty) } ?? true)
    }

    private func isInScope(_ question: QuestionSummary, _ scope: PracticeScope, history: PracticeHistory) -> Bool {
        switch scope {
        case .all: true
        case .wrongOnly: history.lastResult[question.id] == false
        case .unanswered: history.lastResult[question.id] == nil
        case .flagged: history.flagged.contains(question.id)
        }
    }

    // MARK: - 手順 4: fresh と recent への分割

    /// recent は出題の古い順(同時刻なら ID 順)に並べて返す
    func splitByRecency(
        _ questions: [QuestionSummary], history: PracticeHistory, now: Date
    ) -> (fresh: [QuestionSummary], recent: [QuestionSummary]) {
        let exclusion = parameters.recentExclusion.timeInterval
        let isRecent = { (question: QuestionSummary) -> Bool in
            guard let servedAt = history.lastServedAt[question.id] else { return false }
            return now.timeIntervalSince(servedAt) < exclusion
        }
        let recent = questions.filter(isRecent).enumerated().sorted { lhs, rhs in
            let lhsServedAt = history.lastServedAt[lhs.element.id] ?? .distantPast
            let rhsServedAt = history.lastServedAt[rhs.element.id] ?? .distantPast
            return lhsServedAt != rhsServedAt ? lhsServedAt < rhsServedAt : lhs.offset < rhs.offset
        }.map(\.element)
        return (questions.filter { !isRecent($0) }, recent)
    }

    // MARK: - 手順 5: 抽出

    private func draw(
        _ count: Int, from questions: [QuestionSummary], strategy: SelectionStrategy, history: PracticeHistory,
        using rng: inout some RandomNumberGenerator
    ) -> [String] {
        switch strategy {
        case .random:
            return DeterministicShuffle.shuffled(questions, using: &rng).prefix(count).map(\.id)
        case .weaknessFirst(let domainScores):
            // Efraimidis–Spirakis: 鍵 u^(1/w) の大きい順に取る(重み付きの非復元抽出)。
            // 同じ順になる log(u) / w を鍵にする(w が小さいときに u^(1/w) が 0 にアンダーフローするのを避ける)
            let keys = questions.map { log(Self.unitRandom(using: &rng)) / weight(of: $0, history: history, domainScores: domainScores) }
            return zip(questions, keys).enumerated()
                .sorted { lhs, rhs in
                    lhs.element.1 != rhs.element.1 ? lhs.element.1 > rhs.element.1 : lhs.offset < rhs.offset
                }
                .prefix(count)
                .map(\.element.0.id)
        }
    }

    /// 弱点優先の重み `max(minimumWeight, 1 − score_d) × 未解答ボーナス × 誤答ボーナス`。
    /// score のないドメイン(まだ準備度を算出していない)は score 0、つまり最も弱いとして扱う
    func weight(of question: QuestionSummary, history: PracticeHistory, domainScores: [Int: Double]) -> Double {
        let base = max(parameters.minimumWeight, 1 - (domainScores[question.domain] ?? 0))
        let bonus = switch history.lastResult[question.id] {
        case .none: parameters.unansweredBonus
        case .some(false): parameters.wrongBonus
        case .some(true): 1.0
        }
        return base * bonus
    }

    /// (0, 1] の一様な乱数(53 ビット)。標準ライブラリの `random(in:using:)` は版の間で同じとは限らないので使わない
    static func unitRandom(using rng: inout some RandomNumberGenerator) -> Double {
        (Double(rng.next() >> 11) + 1) / 9_007_199_254_740_992  // 2^53
    }
}
