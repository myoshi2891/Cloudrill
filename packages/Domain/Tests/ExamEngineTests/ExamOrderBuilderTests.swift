import Testing
import DomainModels
import DomainTestSupport
import StudyModels
@testable import ExamEngine

@Suite("ExamOrderBuilder")
struct ExamOrderBuilderTests {
    /// Q1〜Q3 は選択肢 a〜d、Q4 は a〜e
    private let questions: [String: Question] = Dictionary(uniqueKeysWithValues: [
        ("Q1", QuestionBuilder.single().with(\.id, "Q1").build()),
        ("Q2", QuestionBuilder.single().with(\.id, "Q2").build()),
        ("Q3", QuestionBuilder.single().with(\.id, "Q3").build()),
        ("Q4", QuestionBuilder.multiple(count: 2, correct: ["a", "b"]).with(\.id, "Q4").build()),
    ])

    private func make(_ ids: [String], shuffle: Bool, seed: UInt64 = 7) throws(QuestionOrderError) -> QuestionOrder {
        var rng = SeededGenerator(seed: seed)
        return try ExamOrderBuilder.make(questionIDs: ids, questions: questions, shuffleChoices: shuffle, using: &rng)
    }

    @Test("模試の問題の順をそのまま使う")
    func keepsExamSetOrder() throws {
        // Act
        let order = try make(["Q3", "Q1", "Q2"], shuffle: true)
        // Assert
        #expect(order.items.map(\.questionID) == ["Q3", "Q1", "Q2"])
    }

    @Test("シャッフルしなければ選択肢は元の並び")
    func noShuffleKeepsChoiceOrder() throws {
        // Act
        let order = try make(["Q1", "Q4"], shuffle: false)
        // Assert
        #expect(order.items.map(\.choiceIDs) == [["a", "b", "c", "d"], ["a", "b", "c", "d", "e"]])
    }

    @Test("同じ seed なら同じ並び")
    func shuffleIsDeterministic() throws {
        // Act
        let first = try make(["Q1", "Q2", "Q4"], shuffle: true)
        let second = try make(["Q1", "Q2", "Q4"], shuffle: true)
        // Assert
        #expect(first == second)
    }

    /// 期待値は、同じアルゴリズムの Python の参照実装(SplitMix64 + Lemire の上限付き乱数 + Fisher–Yates)で求めた。
    /// アルゴリズムを変えた場合だけ更新する(保存済みの出題順の意味が変わるため)。
    @Test("seed 7 の並びは固定(ゴールデン)")
    func shuffleGolden() throws {
        // Act
        let order = try make(["Q3", "Q4"], shuffle: true)
        // Assert
        #expect(order.items.map(\.choiceIDs) == [["c", "d", "a", "b"], ["d", "e", "a", "b", "c"]])
    }

    @Test("どの seed でも、選択肢の並べ替えになっている", arguments: 0..<100)
    func shuffleKeepsAllChoices(seed: UInt64) throws {
        // Act
        let order = try make(["Q1"], shuffle: true, seed: seed)
        // Assert
        #expect(order.items[0].choiceIDs.sorted() == ["a", "b", "c", "d"])
    }

    @Test("保存した選択肢の ID が問題と異なればエラー(問題が改訂された場合など)")
    func restoreValidatesChoices() throws {
        // Arrange
        let order = QuestionOrder(items: [
            .init(questionID: "Q1", choiceIDs: ["b", "a", "d", "c"]),
            .init(questionID: "Q4", choiceIDs: ["b", "a", "d", "c"]),  // e がない
        ])
        // Act
        let result = Result { () throws(QuestionOrderError) in try ExamOrderBuilder.validate(order, against: questions) }
        // Assert
        guard case .failure(.choicesMismatch(questionID: "Q4")) = result else {
            Issue.record("choicesMismatch(Q4) を期待したが \(result)")
            return
        }
    }

    @Test("問題がなければエラー(作成時と検証時)")
    func missingQuestion() {
        // Act
        let made = Result { () throws(QuestionOrderError) in try make(["Q1", "Q9"], shuffle: false) }
        let validated = Result { () throws(QuestionOrderError) in
            try ExamOrderBuilder.validate(QuestionOrder(items: [.init(questionID: "Q9", choiceIDs: [])]), against: questions)
        }
        // Assert
        for result in [made.map { _ in () }, validated] {
            guard case .failure(.missingQuestion("Q9")) = result else {
                Issue.record("missingQuestion(Q9) を期待したが \(result)")
                continue
            }
        }
    }

    @Test("Fisher–Yates は自前の実装で、同じ乱数列から期待値の表どおりに並べる")
    func fisherYatesDoesNotUseStdlibShuffle() {
        // Arrange
        var rng = SeededGenerator(seed: 42)
        // Act
        let four = DeterministicShuffle.shuffled(["a", "b", "c", "d"], using: &rng)
        let five = DeterministicShuffle.shuffled(["a", "b", "c", "d", "e"], using: &rng)
        // Assert
        #expect(four == ["b", "d", "a", "c"])
        #expect(five == ["e", "d", "c", "a", "b"])
    }
}
