import Testing
import DomainModels
import DomainTestSupport
import StudyModels
@testable import ExamEngine

@Suite("AnswerEvaluator")
struct AnswerEvaluatorTests {
    // MARK: - SingleChoiceEvaluator

    @Test("単一選択: 正解を選べば正答")
    func singleCorrect() throws {
        // Arrange
        let question = QuestionBuilder.single(correct: "b").build()
        // Act
        let result = try SingleChoiceEvaluator().evaluate(.choices(["b"]), for: question)
        // Assert
        #expect(result)
    }

    @Test("単一選択: 不正解を選べば誤答")
    func singleWrong() throws {
        // Arrange
        let question = QuestionBuilder.single(correct: "b").build()
        // Act
        let result = try SingleChoiceEvaluator().evaluate(.choices(["a"]), for: question)
        // Assert
        #expect(!result)
    }

    @Test("単一選択: 2つ選べば誤答(エラーにはしない)")
    func singleTwoSelections() throws {
        // Arrange
        let question = QuestionBuilder.single(correct: "b").build()
        // Act
        let result = try SingleChoiceEvaluator().evaluate(.choices(["a", "b"]), for: question)
        // Assert
        #expect(!result)
    }

    @Test("単一選択: 存在しない選択肢 ID は誤答")
    func singleUnknownChoice() throws {
        // Arrange
        let question = QuestionBuilder.single(correct: "b").build()
        // Act
        let result = try SingleChoiceEvaluator().evaluate(.choices(["z"]), for: question)
        // Assert
        #expect(!result)
    }

    // MARK: - MultipleChoiceEvaluator

    @Test("複数選択は、正解の集合と完全に一致したときだけ正答になる(部分点なし)", arguments: [
        (["a", "c"], true),
        (["a"], false),            // 不足
        (["a", "b", "c"], false),  // 過剰
        (["b", "d"], false),       // 個数は同じだが不正解
    ])
    func multipleExactMatch(selected: [String], expected: Bool) throws {
        // Arrange
        let question = QuestionBuilder.multiple(count: 2, correct: ["a", "c"]).build()
        // Act
        let result = try MultipleChoiceEvaluator().evaluate(.choices(Set(selected)), for: question)
        // Assert
        #expect(result == expected)
    }

    @Test("担当外の出題形式はエラー")
    func evaluatorRejectsOtherKind() {
        // Arrange
        let question = QuestionBuilder.multiple(count: 2, correct: ["a", "c"]).build()
        // Act / Assert
        #expect(throws: EvaluationError.unsupportedKind(.multiple)) {
            try SingleChoiceEvaluator().evaluate(.choices(["a", "c"]), for: question)
        }
    }

    // MARK: - AnswerEvaluatorRegistry

    @Test("standard は出題形式ごとに判定を振り分ける")
    func registryDispatchesByKind() throws {
        // Arrange
        let registry = AnswerEvaluatorRegistry.standard
        let single = QuestionBuilder.single(correct: "b").build()
        let multiple = QuestionBuilder.multiple(count: 2, correct: ["a", "c"]).build()
        // Act / Assert
        #expect(try registry.evaluate(.choices(["b"]), for: single))
        #expect(try !registry.evaluate(.choices(["a"]), for: single))
        #expect(try registry.evaluate(.choices(["a", "c"]), for: multiple))
        #expect(try !registry.evaluate(.choices(["a"]), for: multiple))
    }

    @Test("登録のない出題形式はエラー")
    func registryUnsupportedKind() throws {
        // Arrange
        let registry = try AnswerEvaluatorRegistry([SingleChoiceEvaluator()])
        let question = QuestionBuilder.multiple(count: 2, correct: ["a", "c"]).build()
        // Act / Assert
        #expect(!registry.supports(.multiple))
        #expect(throws: EvaluationError.unsupportedKind(.multiple)) {
            try registry.evaluate(.choices(["a", "c"]), for: question)
        }
    }

    @Test("同じ出題形式を2つ登録するとエラー")
    func registryRejectsDuplicateKind() {
        // Act / Assert
        #expect(throws: AnswerEvaluatorRegistry.RegistryError.duplicateKind(.single)) {
            try AnswerEvaluatorRegistry([SingleChoiceEvaluator(), SingleChoiceEvaluator()])
        }
    }

    @Test("standard はすべての出題形式に対応する(形式を追加したときの登録漏れを検出する)", arguments: QuestionKind.allCases)
    func registryCoversAllKinds(kind: QuestionKind) {
        // Act / Assert
        #expect(AnswerEvaluatorRegistry.standard.supports(kind))
    }
}
