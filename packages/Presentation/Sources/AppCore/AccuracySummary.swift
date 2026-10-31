import DomainModels
import StudyModels

/// 解答記録時のドメインとサブ項目の組。改版で ID が別ドメインへ移っても旧解答を混ぜない。
public struct SubObjectiveKey: Hashable, Sendable {
    public var domain: Int
    public var subObjective: String
    public init(domain: Int, subObjective: String) { self.domain = domain; self.subObjective = subObjective }
}

/// 解答時点の分類で全履歴を集計する。未解答は 0% ではなく nil、同率は定義順。
public struct AccuracySummary: Sendable {
    public let byDomain: [Int: ScoreTally]
    public let bySubObjective: [SubObjectiveKey: ScoreTally]
    public let weakestDomain: Int?

    public init(definition: ExamDefinition, answers: [AnswerFact]) {
        self.init(definition: definition, outcomes: answers.filter { $0.examID == definition.id }
            .map { AnswerOutcome(domain: $0.domain, subObjective: $0.subObjective, isCorrect: $0.isCorrect) })
    }

    /// outcomes は definition の試験に絞り込み済みであること。
    public init(definition: ExamDefinition, outcomes: [AnswerOutcome]) {
        var domains = Dictionary(uniqueKeysWithValues: definition.domains.map { ($0.id, ScoreTally(correct: 0, total: 0)) })
        var subs: [SubObjectiveKey: ScoreTally] = [:]
        for answer in outcomes where domains[answer.domain] != nil {
            domains[answer.domain]!.total += 1
            domains[answer.domain]!.correct += answer.isCorrect ? 1 : 0
            let key = SubObjectiveKey(domain: answer.domain, subObjective: answer.subObjective)
            subs[key, default: .init(correct: 0, total: 0)].total += 1
            subs[key, default: .init(correct: 0, total: 0)].correct += answer.isCorrect ? 1 : 0
        }
        byDomain = domains; bySubObjective = subs
        var weakest: Int?
        var lowest = Double.infinity
        for domain in definition.domains {
            if let ratio = domains[domain.id]?.ratio, ratio < lowest {
                weakest = domain.id; lowest = ratio
            }
        }
        weakestDomain = weakest
    }
}
