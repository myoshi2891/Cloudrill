import DomainModels
import StudyModels

public struct ScoringInput: Sendable {
    public var definition: ExamDefinition
    public var questions: [Question]
    /// 問題 ID → 選択。キーがなければ未解答
    public var answers: [String: AnswerSelection]

    public init(definition: ExamDefinition, questions: [Question], answers: [String: AnswerSelection]) {
        self.definition = definition
        self.questions = questions
        self.answers = answers
    }
}

/// 採点方式(DDD 4.9)。方式は exam.yaml の `scoring.policy` で選ぶ。
public protocol ScoringPolicy: Sendable {
    var kind: ScoringPolicyKind { get }
    func score(_ input: ScoringInput, evaluators: AnswerEvaluatorRegistry) throws(EvaluationError) -> ExamResult
}

public enum ScoringPolicies {
    /// ScoringPolicyKind は構造語彙なので、すべての case に実装がある(switch の網羅性で保証する)
    public static func policy(for kind: ScoringPolicyKind) -> any ScoringPolicy {
        switch kind {
        case .allOrNothing: AllOrNothingScoring()
        }
    }
}

/// 1問の判定結果
struct QuestionOutcome {
    var question: Question
    var isCorrect: Bool
}

extension Sequence<QuestionOutcome> {
    /// キーごとに正答数と出題数を数える。キーが nil の問題は数えない。
    /// `initialKeys` は出題がなくても 0/0 で結果に含めるキー。
    func tally<Key: Hashable>(by key: (Question) -> Key?, initialKeys: [Key] = []) -> [Key: ScoreTally] {
        var result = Dictionary(uniqueKeysWithValues: initialKeys.map { ($0, ScoreTally(correct: 0, total: 0)) })
        for outcome in self {
            guard let value = key(outcome.question) else { continue }
            var tally = result[value, default: ScoreTally(correct: 0, total: 0)]
            tally.total += 1
            if outcome.isCorrect { tally.correct += 1 }
            result[value] = tally
        }
        return result
    }
}
