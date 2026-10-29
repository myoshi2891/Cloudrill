import Foundation
import Testing
import AppCore
import HomeFeature
import DomainModels
import DomainInterfaces
import StudyModels
import DomainTestSupport
import QuestionSelector
import FSRS

@MainActor struct HomeViewModelTests {
    private func model(answers: [AnswerFact] = [], cards: [FSRSCard] = [], attempt: AttemptSnapshot? = nil,
                       failing: Bool = false) throws -> HomeViewModel {
        HomeViewModel(definition: try SelectionFixtures.content("test-beta").definition,
                      answers: HomeAnswers(answers, failing: failing), cards: HomeCards(cards),
                      attempts: SelectionAttempts(attempt), time: FixedTimeSource(SelectionFixtures.now), router: AppRouter())
    }
    @Test func showsExamNameAndNoDataYet() async throws {
        let vm = try model()
        await vm.refresh()
        #expect(vm.title == "BETA")
        #expect(vm.state.weakDomain == nil)
        #expect(vm.state.dueCards == 0)
        #expect(vm.state.isLoaded)
        vm.startLearning()
        #expect(vm.router.path(for: .exam) == [.practiceSetup(nil)])
    }
    @Test func dueCardCount() async throws {
        var due = FSRSCard.new(at: SelectionFixtures.now)
        due.phase = .review
        var future = due; future.due = future.due.addingTimeInterval(1)
        let vm = try model(cards: Array(repeating: due, count: 42) + [future, .new(at: SelectionFixtures.now)])
        await vm.refresh()
        #expect(vm.state.dueCards == 42)
        vm.reviewCards()
        #expect(vm.router.selectedTab == .cards)
    }
    @Test func weakestDomainAndExamIsolation() async throws {
        let facts = [fact(domain: 1, correct: true), fact(domain: 4, correct: false),
                     fact(domain: 4, correct: true), fact(domain: 2, correct: false, examID: "test-alpha")]
        let vm = try model(answers: facts)
        await vm.refresh()
        #expect(vm.state.weakDomain == 4)
        vm.practiceWeakDomain()
        #expect(vm.router.path(for: .exam) == [.practiceSetup(.domain(4))])
        let summary = AccuracySummary(definition: try SelectionFixtures.content("test-beta").definition, answers: facts)
        #expect(summary.byDomain[4]?.ratio == 0.5)
        #expect(summary.byDomain[2]?.ratio == nil)
        #expect(summary.bySubObjective["4.1"]?.total == 2)
    }
    @Test func resumeBanner() async throws {
        var attempt = try SelectionFixtures.attempt(); attempt.examID = "test-beta"
        let vm = try model(attempt: attempt)
        await vm.refresh()
        #expect(vm.state.resumeAttemptID == attempt.id)
        vm.resumeExam()
        #expect(vm.router.path(for: .exam) == [.examSession(attemptID: attempt.id)])
    }
    @Test func failureIsNotEmptyHistory() async throws {
        let vm = try model(failing: true)
        await vm.refresh()
        #expect(vm.state.alert == .persistenceFailed)
        #expect(!vm.state.isLoaded)
        #expect(!vm.state.isLoading)
    }
    @Test func tiedDomainsFollowDefinitionOrder() throws {
        let summary = AccuracySummary(definition: try SelectionFixtures.content("test-beta").definition,
                                      answers: [fact(domain: 4, correct: false), fact(domain: 2, correct: false)])
        #expect(summary.weakestDomain == 2)
    }
    @Test func refreshReplacesHistoryAndRetryClearsError() async throws {
        let answers = HomeAnswers([fact(domain: 4, correct: false)], failing: false)
        let vm = HomeViewModel(definition: try SelectionFixtures.content("test-beta").definition,
            answers: answers, cards: HomeCards([]), attempts: SelectionAttempts(),
            time: FixedTimeSource(SelectionFixtures.now), router: AppRouter())
        await vm.refresh()
        #expect(vm.state.weakDomain == 4)
        await answers.update([], failing: true)
        await vm.refresh()
        #expect(vm.state.alert == .persistenceFailed)
        #expect(vm.state.weakDomain == 4)
        await answers.update([], failing: false)
        await vm.refresh()
        #expect(vm.state.alert == nil)
        #expect(vm.state.weakDomain == nil)
    }
    @Test func disabledCardsAreNotLoaded() async throws {
        var definition = try SelectionFixtures.content("test-beta").definition
        definition.features.flashcards = false
        var card = FSRSCard.new(at: SelectionFixtures.now); card.phase = .review
        let cards = HomeCards([card])
        let vm = HomeViewModel(definition: definition, answers: HomeAnswers([], failing: false),
            cards: cards, attempts: SelectionAttempts(), time: FixedTimeSource(SelectionFixtures.now), router: AppRouter())
        await vm.refresh()
        #expect(vm.state.dueCards == 0)
        #expect(await cards.readCount == 0)
    }
    private func fact(domain: Int, correct: Bool, examID: ExamID = "test-beta") -> AnswerFact {
        .init(examID: examID, questionID: "Q", questionRevision: 1, domain: domain,
              subObjective: "\(domain).1", caseStudy: nil, selection: .choices(["a"]), isCorrect: correct,
              mode: .practice, answeredAt: SelectionFixtures.now, elapsedSeconds: 10)
    }
}

private actor HomeAnswers: AnswerHistoryRepository {
    var facts: [AnswerFact]
    var failing: Bool
    init(_ facts: [AnswerFact], failing: Bool) { self.facts = facts; self.failing = failing }
    func update(_ facts: [AnswerFact], failing: Bool) { self.facts = facts; self.failing = failing }
    func answers(examID: ExamID) throws(PersistenceError) -> [AnswerFact] {
        if failing { throw .saveFailed("test") }; return facts
    }
    func record(_ answer: AnswerFact) throws(PersistenceError) {}
    func practiceHistory(examID: ExamID, now: Date) throws(PersistenceError) -> PracticeHistory { .init() }
    func markServed(questionIDs: [String], examID: ExamID, at date: Date) throws(PersistenceError) {}
    func setFlag(_ flagged: Bool, questionID: String, examID: ExamID, at date: Date) throws(PersistenceError) {}
}
private actor HomeCards: CardStateRepository {
    var readCount = 0
    let values: [FSRSCard]
    init(_ values: [FSRSCard]) { self.values = values }
    func card(id: String, examID: ExamID) throws(PersistenceError) -> FSRSCard? { nil }
    func apply(_ outcome: ReviewOutcome, cardID: String, examID: ExamID) throws(PersistenceError) {}
    func scheduledCards(examID: ExamID) throws(PersistenceError) -> [(id: String, card: FSRSCard)] {
        readCount += 1
        return values.enumerated().map { (String($0.offset), $0.element) }
    }
    func reviewCount(examID: ExamID, on day: DateInterval) throws(PersistenceError) -> (introduced: Int, reviewed: Int) { (0, 0) }
    func addCardFromQuestion(questionID: String, examID: ExamID, at date: Date) throws(PersistenceError) {}
}
