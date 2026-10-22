import DomainModels
import StudyModels

/// 出題形式から判定を引く。問題の `type.kind` で振り分ける。
public struct AnswerEvaluatorRegistry: Sendable {
    public enum RegistryError: Error, Equatable {
        case duplicateKind(QuestionKind)
    }

    private let evaluators: [QuestionKind: any AnswerEvaluator]

    public init(_ evaluators: [any AnswerEvaluator]) throws(RegistryError) {
        var byKind: [QuestionKind: any AnswerEvaluator] = [:]
        for evaluator in evaluators {
            guard byKind[evaluator.kind] == nil else { throw .duplicateKind(evaluator.kind) }
            byKind[evaluator.kind] = evaluator
        }
        self.evaluators = byKind
    }

    private init(uniqueEvaluators: [any AnswerEvaluator]) {
        evaluators = Dictionary(uniqueKeysWithValues: uniqueEvaluators.map { ($0.kind, $0) })
    }

    /// 製品で使う登録。全形式に対応していることは AnswerEvaluatorTests.registryCoversAllKinds で確認する。
    public static let standard = AnswerEvaluatorRegistry(uniqueEvaluators: [
        SingleChoiceEvaluator(),
        MultipleChoiceEvaluator(),
    ])

    public func supports(_ kind: QuestionKind) -> Bool {
        evaluators[kind] != nil
    }

    public func evaluate(_ selection: AnswerSelection, for question: Question) throws(EvaluationError) -> Bool {
        guard let evaluator = evaluators[question.type.kind] else {
            throw .unsupportedKind(question.type.kind)
        }
        return try evaluator.evaluate(selection, for: question)
    }
}
