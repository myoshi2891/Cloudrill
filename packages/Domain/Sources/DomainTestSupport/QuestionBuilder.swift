import Foundation
import DomainModels

/// テスト用の問題。既定値で最小の有効な問題(Schema を満たす形)を作り、テストに関係する値だけを `with` で変える。
public struct QuestionBuilder: Sendable {
    public var question: Question

    public init(_ question: Question) { self.question = question }

    public func with<Value>(_ keyPath: WritableKeyPath<Question, Value>, _ value: Value) -> Self {
        var copy = self
        copy.question[keyPath: keyPath] = value
        return copy
    }

    public func build() -> Question { question }

    /// 単一選択(選択肢 a〜d)
    public static func single(correct: String = "a") -> Self {
        make(type: .single, choiceIDs: ["a", "b", "c", "d"], correct: [correct])
    }

    /// 複数選択(選択肢 a〜e)
    public static func multiple(count: Int, correct: [String]) -> Self {
        make(type: .multiple(count: count), choiceIDs: ["a", "b", "c", "d", "e"], correct: Set(correct))
    }

    private static func make(type: QuestionType, choiceIDs: [String], correct: Set<String>) -> Self {
        Self(Question(
            id: "Q-1.1-0001",
            revision: 1,
            examGuideVersion: "1.0",
            domain: 1,
            subObjective: "1.1",
            caseStudy: nil,
            type: type,
            difficulty: 3,
            wafPillars: [],
            keywords: [],
            examSets: [],
            stem: LocalizedText(ja: "ダミーの問題文"),
            choices: choiceIDs.map { id in
                Choice(
                    id: id,
                    text: LocalizedText(ja: "ダミーの選択肢 \(id)"),
                    isCorrect: correct.contains(id),
                    rationale: LocalizedText(ja: "ダミーの解説 \(id)")
                )
            },
            references: []
        ))
    }
}
