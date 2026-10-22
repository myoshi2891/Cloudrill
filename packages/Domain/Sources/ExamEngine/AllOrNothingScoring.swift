import DomainModels
import StudyModels

/// 1問ごとに正誤だけを数える(部分点なし)。未解答は誤答として数える(BDD 6.3)。
public struct AllOrNothingScoring: ScoringPolicy {
    public let kind = ScoringPolicyKind.allOrNothing

    public init() {}

    public func score(_ input: ScoringInput, evaluators: AnswerEvaluatorRegistry) throws(EvaluationError) -> ExamResult {
        // 未解答の問題も含めて先に確かめる(解答の有無でエラーになるかどうかが変わらないようにする)
        if let unsupported = input.questions.first(where: { !evaluators.supports($0.type.kind) }) {
            throw .unsupportedKind(unsupported.type.kind)
        }

        var outcomes: [QuestionOutcome] = []
        var unansweredCount = 0
        for question in input.questions {
            guard let selection = input.answers[question.id] else {
                unansweredCount += 1
                outcomes.append(QuestionOutcome(question: question, isCorrect: false))
                continue
            }
            let isCorrect = try evaluators.evaluate(selection, for: question)
            outcomes.append(QuestionOutcome(question: question, isCorrect: isCorrect))
        }

        let definition = input.definition
        return ExamResult(
            total: ScoreTally(correct: outcomes.filter(\.isCorrect).count, total: outcomes.count),
            byDomain: outcomes.tally(by: \.domain, initialKeys: definition.domains.map(\.id)),
            byCaseStudy: definition.features.caseStudies ? outcomes.tally(by: \.caseStudy) : [:],
            unansweredCount: unansweredCount
        )
    }
}
