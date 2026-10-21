import Testing
import DomainModels
import DomainTestSupport
import StudyModels
@testable import ExamEngine

@Suite("Scoring")
struct ScoringTests {
    private let policy = AllOrNothingScoring()

    private func question(_ id: String, domain: Int = 1, caseStudy: CaseStudyID? = nil) -> Question {
        QuestionBuilder.single(correct: "a")
            .with(\.id, id)
            .with(\.domain, domain)
            .with(\.caseStudy, caseStudy)
            .build()
    }

    private func score(
        _ definition: ExamDefinition, _ questions: [Question], _ answers: [String: AnswerSelection]
    ) throws -> ExamResult {
        try policy.score(
            ScoringInput(definition: definition, questions: questions, answers: answers),
            evaluators: .standard
        )
    }

    @Test("正解の数を数える")
    func totalCountsCorrectAnswers() throws {
        // Arrange
        let questions = (1...4).map { question("Q\($0)") }
        let answers: [String: AnswerSelection] = ["Q1": .choices(["a"]), "Q2": .choices(["a"]), "Q3": .choices(["a"]), "Q4": .choices(["b"])]
        // Act
        let result = try score(ExamDefinitionBuilder.alphaLike().build(), questions, answers)
        // Assert
        #expect(result.total == ScoreTally(correct: 3, total: 4))
        #expect(result.unansweredCount == 0)
    }

    @Test("未解答は誤答として数える")
    func unansweredIsIncorrect() throws {
        // Arrange
        let questions = (1...4).map { question("Q\($0)") }
        let answers: [String: AnswerSelection] = ["Q1": .choices(["a"]), "Q2": .choices(["a"])]
        // Act
        let result = try score(ExamDefinitionBuilder.alphaLike().build(), questions, answers)
        // Assert
        #expect(result.total == ScoreTally(correct: 2, total: 4))
        #expect(result.unansweredCount == 2)
    }

    @Test("byDomain は試験定義の全ドメインを持つ(出題がないドメインは 0/0)")
    func byDomainHasEveryDomain() throws {
        // Arrange
        let questions = [question("Q1", domain: 1), question("Q2", domain: 2)]
        // Act
        let result = try score(ExamDefinitionBuilder.alphaLike().build(), questions, ["Q1": .choices(["a"])])
        // Assert
        #expect(result.byDomain == [
            1: ScoreTally(correct: 1, total: 1),
            2: ScoreTally(correct: 0, total: 1),
            3: ScoreTally(correct: 0, total: 0),
            4: ScoreTally(correct: 0, total: 0),
            5: ScoreTally(correct: 0, total: 0),
            6: ScoreTally(correct: 0, total: 0),
        ])
    }

    @Test("ドメイン数の違う試験では、その試験のドメインだけを持つ")
    func byDomainForBeta() throws {
        // Arrange
        let questions = [question("Q1", domain: 2)]
        // Act
        let result = try score(ExamDefinitionBuilder.betaLike().build(), questions, [:])
        // Assert
        #expect(result.byDomain.keys.sorted() == [1, 2, 3, 4])
    }

    @Test("byCaseStudy は出題のあったケースごとに数える")
    func byCaseStudy() throws {
        // Arrange
        let questions = [
            question("Q1", caseStudy: "case-a"),
            question("Q2", caseStudy: "case-a"),
            question("Q3"),
            question("Q4"),
        ]
        let answers: [String: AnswerSelection] = ["Q1": .choices(["a"]), "Q2": .choices(["b"]), "Q3": .choices(["a"])]
        // Act
        let result = try score(ExamDefinitionBuilder.alphaLike().build(), questions, answers)
        // Assert
        #expect(result.byCaseStudy == ["case-a": ScoreTally(correct: 1, total: 2)])
    }

    @Test("ケース機能が無効な試験では byCaseStudy は空")
    func byCaseStudyEmptyWhenDisabled() throws {
        // Arrange
        let questions = [question("Q1"), question("Q2", domain: 3)]
        // Act
        let result = try score(ExamDefinitionBuilder.betaLike().build(), questions, ["Q1": .choices(["a"])])
        // Assert
        #expect(result.byCaseStudy.isEmpty)
    }

    @Test("ドメイン別の合計が全体と一致し、素朴な数え直しとも一致する(AC-03)", arguments: 0..<20)
    func domainTotalsSumToTotal(seed: UInt64) throws {
        // Arrange
        var rng = SeededGenerator(seed: seed)
        let definition = ExamDefinitionBuilder.alphaLike().build()
        let domainIDs = definition.domains.map(\.id)
        let caseIDs: [CaseStudyID?] = [nil] + definition.caseStudies.map { $0 }
        var questions: [Question] = []
        var answers: [String: AnswerSelection] = [:]
        for index in 0..<55 {
            let id = "Q-\(index)"
            let builder: QuestionBuilder = Bool.random(using: &rng)
                ? .single(correct: ["a", "b", "c", "d"].randomElement(using: &rng) ?? "a")
                : .multiple(count: 2, correct: ["a", "c"])
            questions.append(builder
                .with(\.id, id)
                .with(\.domain, domainIDs.randomElement(using: &rng) ?? 1)
                .with(\.caseStudy, caseIDs.randomElement(using: &rng) ?? nil)
                .build())
            switch Int.random(in: 0..<3, using: &rng) {
            case 0: break  // 未解答
            case 1: answers[id] = .choices(Set(questions[index].correctChoiceIDs))
            default: answers[id] = .choices([["a", "b", "c", "d", "e"].randomElement(using: &rng) ?? "a"])
            }
        }
        // Act
        let result = try score(definition, questions, answers)
        // Assert
        let domainCorrect = result.byDomain.values.map(\.correct).reduce(0, +)
        let domainTotal = result.byDomain.values.map(\.total).reduce(0, +)
        #expect(ScoreTally(correct: domainCorrect, total: domainTotal) == result.total)
        var naiveCorrect = 0
        var naiveUnanswered = 0
        for question in questions {
            guard case let .choices(ids) = answers[question.id] else {
                naiveUnanswered += 1
                continue
            }
            if ids == Set(question.correctChoiceIDs) {
                naiveCorrect += 1
            }
        }
        #expect(result.total == ScoreTally(correct: naiveCorrect, total: questions.count))
        #expect(result.unansweredCount == naiveUnanswered)
    }

    @Test("登録のない出題形式の問題があればエラー")
    func unsupportedKindPropagates() throws {
        // Arrange
        let registry = try AnswerEvaluatorRegistry([SingleChoiceEvaluator()])
        let questions = [question("Q1"), QuestionBuilder.multiple(count: 2, correct: ["a", "c"]).with(\.id, "Q2").build()]
        let input = ScoringInput(definition: ExamDefinitionBuilder.alphaLike().build(), questions: questions, answers: [:])
        // Act / Assert
        #expect(throws: EvaluationError.unsupportedKind(.multiple)) {
            try policy.score(input, evaluators: registry)
        }
    }

    @Test("採点方式から実装を引ける")
    func policyForKind() {
        // Act
        let resolved = ScoringPolicies.policy(for: .allOrNothing)
        // Assert
        #expect(resolved is AllOrNothingScoring)
        #expect(resolved.kind == .allOrNothing)
    }
}
