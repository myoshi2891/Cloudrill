import DomainModels
import StudyModels

public enum EvaluationError: Error, Equatable, Sendable {
    case unsupportedKind(QuestionKind)
}

/// 出題形式ごとの解答の判定(DDD 4.9)。出題形式を追加するときは、実装を追加して `AnswerEvaluatorRegistry.standard` に登録する(DDD 4.10 C)。
public protocol AnswerEvaluator: Sendable {
    var kind: QuestionKind { get }
    func evaluate(_ selection: AnswerSelection, for question: Question) throws(EvaluationError) -> Bool
}

/// 単一選択。選択が1つでなければ誤答にする(UI の不具合で複数が送られても、エラーにはしない)。
public struct SingleChoiceEvaluator: AnswerEvaluator {
    public let kind = QuestionKind.single

    public init() {}

    public func evaluate(_ selection: AnswerSelection, for question: Question) throws(EvaluationError) -> Bool {
        guard question.type.kind == kind else { throw .unsupportedKind(question.type.kind) }
        // 正解は1つなので、集合の一致は「1つだけ選び、それが正解」と同じ
        return selection.matchesExactly(question.correctChoiceIDs)
    }
}

/// 複数選択。正解の集合と完全に一致したときだけ正答にする(部分点なし。FR-EXAM-06)。
public struct MultipleChoiceEvaluator: AnswerEvaluator {
    public let kind = QuestionKind.multiple

    public init() {}

    public func evaluate(_ selection: AnswerSelection, for question: Question) throws(EvaluationError) -> Bool {
        guard question.type.kind == kind else { throw .unsupportedKind(question.type.kind) }
        return selection.matchesExactly(question.correctChoiceIDs)
    }
}

extension AnswerSelection {
    /// 選択した ID の集合が、正解の ID の集合と一致するか
    func matchesExactly(_ correctChoiceIDs: [String]) -> Bool {
        switch self {
        case let .choices(ids): ids == Set(correctChoiceIDs)
        }
    }
}
