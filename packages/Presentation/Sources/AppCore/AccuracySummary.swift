import DomainModels
import StudyModels

/// 解答時点の分類で全履歴を集計する。未解答は 0% ではなく nil、同率は定義順。
public struct AccuracySummary: Sendable {
    public let byDomain: [Int: ScoreTally]
    public let bySubObjective: [String: ScoreTally]
    public let weakestDomain: Int?

    public init(definition: ExamDefinition, answers: [AnswerFact]) {
        var domains = Dictionary(uniqueKeysWithValues: definition.domains.map { ($0.id, ScoreTally(correct: 0, total: 0)) })
        var subs: [String: ScoreTally] = [:]
        for answer in answers where answer.examID == definition.id && domains[answer.domain] != nil {
            domains[answer.domain]!.total += 1
            domains[answer.domain]!.correct += answer.isCorrect ? 1 : 0
            subs[answer.subObjective, default: .init(correct: 0, total: 0)].total += 1
            subs[answer.subObjective, default: .init(correct: 0, total: 0)].correct += answer.isCorrect ? 1 : 0
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
