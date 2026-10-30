import Foundation
import Testing
import AppCore
import ExamFeature
import DomainModels
import DomainInterfaces
import StudyModels
import ExamEngine
import DomainTestSupport

@MainActor struct ExamResultViewModelTests {
    @Test func showsTotalsAndDefinitionBreakdownsInSavedOrder() async throws {
        let h = try ResultHarness(count: 55, correct: 40)
        let model = h.resultModel()
        await model.load()
        #expect(model.error == nil)
        #expect(model.result?.total == ScoreTally(correct: 40, total: 55))
        #expect(model.scoreText == "40 / 55 (73%)")
        #expect(model.elapsedMinutes == 98)
        #expect(model.domains.map(\.name) == h.content.definition.domains.map { $0.name.ja })
        #expect(model.domains.first?.tally == ScoreTally(correct: 40, total: 55))
        #expect(model.questions.map(\.id) == h.summary.attempt.snapshot.order.items.map(\.questionID))
        #expect(model.questions.last?.isUnanswered == true)
        model.openExplanation(questionID: "Q0")
        #expect(h.router.path(for: .exam) == [.explanation(attemptID: h.summary.id, questionID: "Q0")])
        #expect(h.resolver.requests.withLock { $0 } == ["1.0.0"])
    }
    @Test func betaShowsFourDomainsAndNoCases() async throws {
        let h = try ResultHarness(examID: "test-beta", count: 2, correct: 1)
        let model = h.resultModel()
        await model.load()
        #expect(model.domains.count == 4)
        #expect(model.cases.isEmpty)
        #expect(model.domains.last?.tally.ratio == nil)
    }
    @Test func domainBreakdownsMatchIndependentAnswerCounts() async throws {
        let h = try ResultHarness(examID: "test-beta", count: 6, correct: 3, distributeDomains: true)
        let model = h.resultModel()
        await model.load()
        #expect(model.domains.map(\.tally) == [
            ScoreTally(correct: 1, total: 2), ScoreTally(correct: 1, total: 2),
            ScoreTally(correct: 1, total: 1), ScoreTally(correct: 0, total: 1),
        ])
        #expect(model.result?.unansweredCount == 1)
    }
    @Test func caseBreakdownAndUnansweredDenominator() async throws {
        let h = try ResultHarness(count: 3, correct: 1, caseQuestions: true)
        let model = h.resultModel()
        await model.load()
        #expect(model.cases.map(\.name) == ["ケース A"])
        #expect(model.cases.first?.tally == ScoreTally(correct: 1, total: 3))
        #expect(model.result?.unansweredCount == 1)
    }
    @Test func missingVersionShowsErrorAndCanRetryWithoutFallback() async throws {
        let h = try ResultHarness()
        h.resolver.fails.withLock { $0 = true }
        let model = h.resultModel()
        await model.load()
        #expect(model.result == nil)
        #expect(model.error != nil)
        h.resolver.fails.withLock { $0 = false }
        await model.load()
        #expect(model.error == nil)
        #expect(model.result != nil)
        #expect(h.resolver.requests.withLock { $0 } == ["1.0.0", "1.0.0"])
    }
    @Test func invalidSavedOrderDoesNotShowPartialResult() async throws {
        let h = try ResultHarness()
        var bad = h.summary
        bad.attempt.snapshot.order = QuestionOrder(items: [.init(questionID: "Q0", choiceIDs: ["missing"])])
        await h.attempts.replace(bad)
        let model = h.resultModel()
        await model.load()
        #expect(model.result == nil)
        #expect(model.error != nil)
    }
    @Test func mismatchedScoreOrUnsubmittedAttemptIsRejected() async throws {
        let h = try ResultHarness()
        var bad = h.summary
        bad.total.correct = 3
        await h.attempts.replace(bad)
        let model = h.resultModel()
        await model.load()
        #expect(model.result == nil)
        #expect(model.error != nil)
        bad = h.summary
        bad.attempt.snapshot.state = .inProgress
        await h.attempts.replace(bad)
        let explanation = h.explanation()
        await explanation.load()
        #expect(explanation.question == nil)
        #expect(explanation.error != nil)
    }
    @Test func overdueSubmissionCapsElapsedTimeAtExamDuration() async throws {
        let h = try ResultHarness()
        var late = h.summary
        late.submittedAt = late.attempt.startedAt.addingTimeInterval(86400)
        late.reason = .timeExpired
        late.attempt.snapshot.state = .submitted(.timeExpired)
        await h.attempts.replace(late)
        let model = h.resultModel()
        await model.load()
        #expect(model.elapsedMinutes == 120)
        #expect(model.summary?.reason == .timeExpired)
    }
}

@MainActor struct ResultHarness {
    let summary: AttemptSummary
    let content: SessionContent
    let resolver: SessionResolver
    let attempts: ResultAttempts
    let cards = SessionCards()
    let router = AppRouter()
    let time = ManualTimeSource(SelectionFixtures.now)
    init(examID: ExamID = "test-alpha", count: Int = 3, correct: Int = 1,
         caseQuestions: Bool = false, flashcards: Bool = true, docs: Bool = true,
         docsEnabled: Bool = true, distributeDomains: Bool = false) throws {
        var base = try ExamFixture(examID)
        base.definition.features.flashcards = flashcards
        base.definition.features.docs = docsEnabled
        if docs {
            base.docsIndex = [try JSONDecoder().decode(DocEntry.self, from: Data(
                #"{"subObjective":"3.2","title":"関連資料","references":[],"path":"docs/3.2.md"}"#.utf8))]
        }
        let questions = (0..<count).map { index in
            var question = QuestionBuilder.single().with(\.id, "Q\(index)")
                .with(\.stem, LocalizedText(ja: "受験時の問題", en: "Original question"))
                .with(\.subObjective, "3.2").with(\.revision, 7)
                .with(\.domain, distributeDomains ? base.definition.domains[index % base.definition.domains.count].id : 1)
                .with(\.caseStudy, caseQuestions ? "A" : nil).build()
            question.choices[1].mistakeTags = [.cost, .opsOverhead]
            question.references = [Reference(title: "出典", url: URL(string: "https://example.com")!, license: .ccBy40),
                                   Reference(title: "リンク", url: URL(string: "https://example.com/link")!, license: .linkOnly)]
            return question
        }
        content = SessionContent(base: base, values: questions.reversed()) // provider の返却順に依存しない。
        resolver = SessionResolver(content: content)
        let order = QuestionOrder(items: questions.map { .init(questionID: $0.id, choiceIDs: $0.choices.map(\.id).reversed()) })
        var session = ExamSession(order: order, duration: .seconds(7200), timerPolicy: .init())
        try session.handle(.start, at: SelectionFixtures.now)
        for (index, question) in questions.enumerated() where index < count - 1 || index < correct {
            try session.select(.choices([index < correct ? "a" : "b"]), for: question.id)
        }
        let date = SelectionFixtures.now.addingTimeInterval(98 * 60)
        try session.handle(.openReview, at: date)
        try session.handle(.submit, at: date)
        summary = AttemptSummary(attempt: AttemptSnapshot(id: UUID(), examID: examID, examSet: 1, packVersion: "1.0.0",
            startedAt: SelectionFixtures.now, snapshot: session.snapshot), submittedAt: date, reason: .user,
            total: ScoreTally(correct: correct, total: count))
        attempts = ResultAttempts(summary)
    }
    func resultModel() -> ExamResultViewModel {
        ExamResultViewModel(examID: summary.attempt.examID, attemptID: summary.id,
            resolver: resolver, attempts: attempts, router: router)
    }
    func explanation(_ questionID: String = "Q0") -> ExplanationViewModel {
        ExplanationViewModel(examID: summary.attempt.examID, attemptID: summary.id, questionID: questionID,
            resolver: resolver, attempts: attempts, cards: cards, time: time, router: router)
    }
}

actor ResultAttempts: ExamAttemptRepository {
    var summary: AttemptSummary
    init(_ summary: AttemptSummary) { self.summary = summary }
    func replace(_ value: AttemptSummary) { summary = value }
    func history(examID: ExamID) throws(PersistenceError) -> [AttemptSummary] { [summary] }
    func inProgress(examID: ExamID) throws(PersistenceError) -> AttemptSnapshot? { nil }
    func start(examID: ExamID, examSet: Int, packVersion: String, snapshot: ExamSession.Snapshot) throws(PersistenceError) -> UUID { throw .notFound }
    func save(snapshot: ExamSession.Snapshot, for attemptID: UUID) throws(PersistenceError) { throw .notFound }
    func record(_ answer: AnswerFact, in attemptID: UUID) throws(PersistenceError) { throw .notFound }
    func finalize(attemptID: UUID, result: ExamResult, reason: SubmitReason, at date: Date) throws(PersistenceError) { throw .notFound }
    func abandon(attemptID: UUID) throws(PersistenceError) { throw .notFound }
}
