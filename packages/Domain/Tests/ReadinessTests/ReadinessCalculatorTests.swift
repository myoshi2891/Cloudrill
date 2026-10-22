import Foundation
import Testing
import DomainModels
import DomainTestSupport
import StudyModels
@testable import Readiness

@Suite("ReadinessCalculator")
struct ReadinessCalculatorTests {
    private struct NotReady: Error { let result: ReadinessResult }

    private let now = Date(timeIntervalSince1970: 1_793_491_200)
    private let alpha = ExamDefinitionBuilder.alphaLike().build()

    private func calculator() throws -> ReadinessCalculator {
        ReadinessCalculator(parameters: try ReadinessParameters())
    }

    private func answer(
        _ questionID: String, domain: Int = 1, correct: Bool = true, daysAgo: Double = 0,
        mode: StudyMode = .practice, examID: ExamID = "test-alpha"
    ) -> AnswerFact {
        AnswerFact(
            examID: examID, questionID: questionID, questionRevision: 1, domain: domain, subObjective: "\(domain).1",
            caseStudy: nil, selection: .choices(["a"]), isCorrect: correct, mode: mode,
            answeredAt: now.addingTimeInterval(-daysAgo * 86_400), elapsedSeconds: 60
        )
    }

    /// ドメインごとに別の ID を持つ問題を `count` 問、すべて今解答する
    private func answers(_ count: Int, domain: Int, correct: Bool = true, mode: StudyMode = .practice) -> [AnswerFact] {
        (0..<count).map { answer("Q-\(domain)-\(mode.rawValue)-\($0)", domain: domain, correct: correct, mode: mode) }
    }

    private func calculate(
        _ answers: [AnswerFact], cardRetentions: [Int: [Double]] = [:], definition: ExamDefinition? = nil
    ) throws -> ReadinessResult {
        try calculator().calculate(ReadinessInput(
            definition: definition ?? alpha, answers: answers, cardRetentions: cardRetentions, now: now
        ))
    }

    private func ready(
        _ answers: [AnswerFact], cardRetentions: [Int: [Double]] = [:], definition: ExamDefinition? = nil
    ) throws -> (score: Double, domains: [Int: DomainReadiness]) {
        let result = try calculate(answers, cardRetentions: cardRetentions, definition: definition)
        guard case let .ready(score, domains) = result else { throw NotReady(result: result) }
        return (score, domains)
    }

    // MARK: - データ収集中

    @Test("ユニークな問題が 30 問未満なら収集中")
    func collectingBelowMinimum() throws {
        // Act
        let result = try calculate(answers(29, domain: 1))
        // Assert
        #expect(result == .collecting(answeredUniqueQuestions: 29, required: 30))
    }

    @Test("同じ問題をくり返し解いても、ユニークな問題の数は増えない")
    func repeatedAnswersDoNotCount() throws {
        // Arrange
        let repeated = (0..<3).flatMap { _ in answers(10, domain: 1) }
        // Act
        let result = try calculate(repeated)
        // Assert
        #expect(repeated.count == 30)
        #expect(result == .collecting(answeredUniqueQuestions: 10, required: 30))
    }

    @Test("exam と practice の解答を合わせて数える")
    func examAndPracticeCount() throws {
        // Act
        let result = try calculate(answers(15, domain: 1, mode: .exam) + answers(15, domain: 1, mode: .practice))
        // Assert
        guard case .ready = result else { throw NotReady(result: result) }
    }

    @Test("drill の解答は数にも正答率にも含めない")
    func drillAnswersExcluded() throws {
        // Act
        let collecting = try calculate(answers(29, domain: 1) + answers(5, domain: 1, correct: false, mode: .drill))
        let readiness = try ready(answers(30, domain: 1) + answers(5, domain: 1, correct: false, mode: .drill))
        // Assert
        #expect(collecting == .collecting(answeredUniqueQuestions: 29, required: 30))
        #expect(readiness.domains[1]?.accuracy == 1)
    }

    @Test("ほかの試験の解答は含めない")
    func otherExamAnswersExcluded() throws {
        // Arrange
        let other = (0..<5).map { answer("X-\($0)", correct: false, examID: "test-beta") }
        // Act
        let collecting = try calculate(answers(29, domain: 1) + other)
        let readiness = try ready(answers(30, domain: 1) + other)
        // Assert
        #expect(collecting == .collecting(answeredUniqueQuestions: 29, required: 30))
        #expect(readiness.domains[1]?.accuracy == 1)
    }

    // MARK: - 計算

    @Test("DDD-P1 3.4 の計算例: ドメイン1の寄与が 1.766667")
    func workedExample() throws {
        // Arrange
        let domain1 = [answer("Q-1-a", correct: true, daysAgo: 0), answer("Q-1-b", correct: false, daysAgo: 14)]
        // Act
        let result = try ready(domain1 + answers(30, domain: 2), cardRetentions: [1: [0.9, 0.7]])
        // Assert
        let d1 = try #require(result.domains[1])
        #expect(approximatelyEqual(try #require(d1.accuracy), 0.666667, tolerance: 1e-6))
        #expect(approximatelyEqual(try #require(d1.retention), 0.8))
        #expect(approximatelyEqual(d1.score, 0.706667, tolerance: 1e-6))
        #expect(approximatelyEqual(d1.coverage, 0.1))
        #expect(approximatelyEqual(0.25 * d1.score * d1.coverage * 100, 1.766667, tolerance: 1e-6))
        // ドメイン2(比重 0.18)は満点・網羅度 1 なので 18
        #expect(approximatelyEqual(result.score, 18 + 1.766667, tolerance: 1e-6))
    }

    @Test("解答の重みは半減期 14 日で減る", arguments: [(0.0, 1.0), (14.0, 0.5), (28.0, 0.25)])
    func halfLife(daysAgo: Double, expected: Double) throws {
        // Act
        let weight = try calculator().recencyWeight(answeredAt: now.addingTimeInterval(-daysAgo * 86_400), now: now)
        // Assert
        #expect(approximatelyEqual(weight, expected))
    }

    @Test("未来の解答(端末間の時計のずれ)は今の解答として扱う")
    func futureAnswerTreatedAsNow() throws {
        // Act
        let weight = try calculator().recencyWeight(answeredAt: now.addingTimeInterval(86_400), now: now)
        // Assert
        #expect(weight == 1)
    }

    @Test("解答が 0 件のドメインは score 0、accuracy は nil")
    func noAnswersDomainScoresZero() throws {
        // Act
        let result = try ready(answers(30, domain: 1), cardRetentions: [3: [0.9]])
        // Assert
        let d3 = try #require(result.domains[3])
        #expect(d3.score == 0)
        #expect(d3.accuracy == nil)
        #expect(d3.coverage == 0)
    }

    @Test("復習済みのカードがなければ、score は正答率だけで決まる", arguments: [[:], [1: []]] as [[Int: [Double]]])
    func noCardsUsesAccuracyOnly(cardRetentions: [Int: [Double]]) throws {
        // Act
        let result = try ready(answers(20, domain: 1) + answers(10, domain: 2, correct: false), cardRetentions: cardRetentions)
        // Assert
        let d1 = try #require(result.domains[1])
        #expect(d1.retention == nil)
        #expect(d1.score == d1.accuracy)
    }

    @Test("網羅度は 1 を上限とする")
    func coverageCapsAtOne() throws {
        // Act
        let result = try ready(answers(25, domain: 1) + answers(5, domain: 2))
        // Assert
        #expect(result.domains[1]?.coverage == 1)
        #expect(result.domains[2]?.coverage == 0.25)
    }

    @Test("比重は試験定義から読む(betaLike で全ドメイン満点なら 100)")
    func weightsFromDefinition() throws {
        // Arrange
        let beta = ExamDefinitionBuilder.betaLike().build()
        let all = (1...4).flatMap { domain in
            (0..<20).map { answer("Q-\(domain)-\($0)", domain: domain, examID: beta.id) }
        }
        // Act
        let result = try ready(all, cardRetentions: [1: [1], 2: [1], 3: [1], 4: [1]], definition: beta)
        // Assert
        #expect(Set(result.domains.keys) == [1, 2, 3, 4])
        #expect(approximatelyEqual(result.score, 100))
    }

    // MARK: - パラメータ

    @Test("既定のパラメータは BDD 6.6 の値")
    func defaultParameters() throws {
        // Act
        let parameters = try ReadinessParameters()
        // Assert
        #expect(parameters.accuracyWeight == 0.7)
        #expect(parameters.retentionWeight == 0.3)
        #expect(parameters.halfLifeDays == 14)
        #expect(parameters.coverageTarget == 20)
        #expect(parameters.minimumUniqueQuestions == 30)
    }

    @Test("正答率と記憶保持率の重みの合計は 1")
    func parametersMustSumToOne() {
        #expect(throws: ReadinessError.weightsMustSumToOne(accuracy: 0.6, retention: 0.3)) {
            try ReadinessParameters(accuracyWeight: 0.6, retentionWeight: 0.3)
        }
    }

    @Test("半減期と網羅度の目標は正の値")
    func nonPositiveParametersAreRejected() {
        #expect(throws: ReadinessError.nonPositiveHalfLife(0)) { try ReadinessParameters(halfLifeDays: 0) }
        #expect(throws: ReadinessError.nonPositiveCoverageTarget(0)) { try ReadinessParameters(coverageTarget: 0) }
    }
}
