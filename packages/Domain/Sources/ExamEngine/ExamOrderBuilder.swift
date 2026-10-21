import DomainModels
import StudyModels

/// 模試の出題順を作る(FR-EXAM-12)。問題の順は模試の定義で固定し、選択肢の並びだけをシャッフルする。
/// 結果は QuestionOrder として保存する(乱数の状態は保存しない。DDD 6.3)。
public enum ExamOrderBuilder {
    public static func make(
        questionIDs: [String],
        questions: [String: Question],
        shuffleChoices: Bool,
        using rng: inout some RandomNumberGenerator
    ) throws(QuestionOrderError) -> QuestionOrder {
        var items: [QuestionOrder.Item] = []
        for questionID in questionIDs {
            guard let question = questions[questionID] else { throw .missingQuestion(questionID) }
            let choiceIDs = question.choices.map(\.id)
            items.append(QuestionOrder.Item(
                questionID: questionID,
                choiceIDs: shuffleChoices ? DeterministicShuffle.shuffled(choiceIDs, using: &rng) : choiceIDs
            ))
        }
        return QuestionOrder(items: items)
    }

    /// 保存した出題順が、現在のコンテンツで使えるかを確かめる(復元時)
    public static func validate(_ order: QuestionOrder, against questions: [String: Question]) throws(QuestionOrderError) {
        for item in order.items {
            guard let question = questions[item.questionID] else { throw .missingQuestion(item.questionID) }
            guard item.choiceIDs.sorted() == question.choices.map(\.id).sorted() else {
                throw .choicesMismatch(questionID: item.questionID)
            }
        }
    }
}
