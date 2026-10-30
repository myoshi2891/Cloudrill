import Foundation
import Testing
import PracticeFeature
import AppCore
import DomainModels
import DomainInterfaces
import DomainTestSupport
import StudyModels
import QuestionSelector

@MainActor struct PracticeViewModelTests {
    @Test func optionsAndPresetsFollowDefinition() throws {
        let beta = try PracticeHarness("test-beta")
        #expect(beta.model.domains.count == 4)
        #expect(beta.model.domains.flatMap(\.subObjectives).map(\.id).contains("NET.1"))
        #expect(beta.model.cases.isEmpty)
        #expect(PracticeViewModel.countOptions == [.fixed(5), .fixed(10), .fixed(20), .all])
        let alpha = try PracticeHarness()
        #expect(alpha.model.cases.count == 4)
        let preset = PracticeViewModel(content: alpha.content, preset: .caseStudy(alpha.model.cases[0]),
            answers: alpha.answers, cards: SessionCards(), time: alpha.time, router: AppRouter(), seedProvider: { 1 })
        #expect(preset.criteria.caseStudies == [alpha.model.cases[0]])
    }
    @Test func emptyAndFailedMarkServedDoNotStart() async throws {
        let h = try PracticeHarness()
        h.model.criteria.domains = [99]
        await h.model.start()
        #expect(h.model.state.alert == "practice.empty")
        #expect(await h.answers.served.isEmpty)
        h.model.criteria.domains = []
        await h.answers.fail(served: true)
        await h.model.start()
        #expect(h.model.state.phase == .setup)
        #expect(h.model.questions.isEmpty)
        await h.answers.fail(served: false)
        await h.model.start()
        #expect(h.model.state.phase == .answering)
    }
    @Test func filtersAndHistoryReachSelectorAndMarkServed() async throws {
        let h = try PracticeHarness()
        await h.answers.setHistory(.init(lastResult: ["Q0": false, "Q1": true, "Q2": false]))
        h.model.criteria.scope = .wrongOnly
        h.model.criteria.domains = [1]
        h.model.criteria.subObjectives = ["1.1"]
        h.model.criteria.difficulty = 2...2
        await h.model.start()
        #expect(h.model.questions.map(\.id) == ["Q0", "Q2"] || h.model.questions.map(\.id) == ["Q2", "Q0"])
        #expect(await h.answers.served == h.model.questions.map(\.id))
    }
    @Test func feedbackOnlyAfterSuccessfulSaveAndRetryDoesNotDuplicate() async throws {
        let h = try PracticeHarness()
        await h.model.start()
        h.model.select("a")
        h.time.advance(by: .seconds(17))
        await h.answers.fail(record: true)
        await h.model.submit()
        #expect(h.model.explanation == nil)
        #expect(h.model.state.phase == .answering)
        await h.answers.fail(record: false)
        h.time.advance(by: .seconds(3))
        await h.model.submit()
        await h.model.submit()
        #expect(h.model.state.phase == .feedback)
        #expect(h.model.explanation?.isCorrect == true)
        #expect(h.model.explanation?.choices.count == 4)
        #expect(h.model.explanation?.selectedIDs == ["a"])
        let facts = await h.answers.facts
        #expect(facts.count == 1)
        #expect(facts.first?.mode == .practice)
        #expect(facts.first?.elapsedSeconds == 17)
        #expect(facts.first?.questionRevision == 1)
        h.model.explanation?.openReport()
        #expect(h.model.explanation?.report?.packVersion == "1.0.0")
    }
    @Test func resultIncludesAllTenAnswersAndDomainBreakdown() async throws {
        let h = try PracticeHarness(count: 10)
        await h.model.start()
        for i in 0..<10 {
            h.model.select(i < 7 ? "a" : "b")
            await h.model.submit()
            h.model.next()
        }
        #expect(h.model.state.phase == .result)
        #expect(h.model.correctCount == 7)
        #expect(h.model.summary.byDomain[1]?.total == 10)
        #expect(h.model.summary.byDomain[1]?.correct == 7)
        #expect(h.model.summary.byDomain[2]?.total == 0)
        #expect(await h.answers.facts.count == 10)
    }
    @Test func multipleSelectionRequiresExactCountAndLocksAfterAnswer() async throws {
        let h = try PracticeHarness(count: 1, multiple: true)
        await h.model.start()
        h.model.select("a")
        await h.model.submit()
        #expect(await h.answers.facts.isEmpty)
        h.model.select("b"); h.model.select("c")
        #expect(h.model.state.selectedIDs == ["a", "b"])
        await h.model.submit()
        h.model.select("a")
        #expect(h.model.state.selectedIDs == ["a", "b"])
    }
    @Test func duplicateSubmitAndSelectionAreIgnoredWhileSaving() async throws {
        let h = try PracticeHarness(count: 1)
        await h.model.start()
        h.model.select("a")
        await h.answers.pauseNextRecord()
        let saving = Task { await h.model.submit() }
        await h.answers.waitForRecord()
        h.model.select("b")
        await h.model.submit()
        h.model.next()
        #expect(h.model.state.selectedIDs == ["a"])
        #expect(h.model.state.phase == .answering)
        await h.answers.resumeRecord()
        await saving.value
        #expect(await h.answers.facts.count == 1)
        #expect(h.model.state.phase == .feedback)
    }
    @Test func flagsPersistAndCanFilterLaterSessions() async throws {
        let h = try PracticeHarness(count: 1)
        await h.model.start()
        await h.model.toggleFlag()
        #expect(h.model.state.flagged == ["Q0"])
        #expect(await h.answers.history.flagged == ["Q0"])
        await h.model.toggleFlag()
        #expect(h.model.state.flagged.isEmpty)
    }
}

@MainActor private struct PracticeHarness {
    let content: PracticeContent
    let answers = PracticeAnswers()
    let time = ManualTimeSource(SelectionFixtures.now)
    let model: PracticeViewModel
    init(_ id: ExamID = "test-alpha", count: Int = 3, multiple: Bool = false) throws {
        var base = try ExamFixture(id)
        if base.definition.features.caseStudies { base.definition.caseStudies = ["A", "B", "C", "D"] }
        content = PracticeContent(base: base, values: (0..<count).map {
            (multiple ? QuestionBuilder.multiple(count: 2, correct: ["a", "b"]) : QuestionBuilder.single())
                .with(\.id, "Q\($0)").with(\.domain, 1).with(\.subObjective, "1.1").with(\.difficulty, 2).build()
        })
        model = PracticeViewModel(content: content, answers: answers, cards: SessionCards(), time: time,
                                  router: AppRouter(), seedProvider: { 42 })
    }
}
private struct PracticeContent: ExamContentProvider {
    let base: ExamFixture
    let values: [Question]
    var definition: ExamDefinition { base.definition }
    var vendor: Vendor { base.vendor }
    var packVersion: String { "1.0.0" }
    var questionIndex: [QuestionIndexEntry] { values.map {
        .init(id: $0.id, revision: $0.revision, domain: $0.domain, subObjective: $0.subObjective,
              caseStudy: $0.caseStudy, difficulty: $0.difficulty, kind: $0.type.kind, examSets: [])
    } }
    var examSets: [ExamSet] { [] }
    var docsIndex: [DocEntry] { [] }
    func questions(ids: [String]) async throws(ContentError) -> [Question] { values.filter { ids.contains($0.id) }.reversed() }
    func flashcards() async throws(ContentError) -> [Flashcard] { [] }
    func caseStudies() async throws(ContentError) -> [CaseStudy] { [] }
    func decisionTrees() async throws(ContentError) -> [DecisionTree] { [] }
    func keywordDrills() async throws(ContentError) -> [KeywordDrill] { [] }
    func docBody(for entry: DocEntry) async throws(ContentError) -> String { "" }
}
private actor PracticeAnswers: AnswerHistoryRepository {
    var facts: [AnswerFact] = []
    var served: [String] = []
    var history = PracticeHistory()
    var recordFails = false, servedFails = false
    func fail(record: Bool) { recordFails = record }
    func fail(served: Bool) { servedFails = served }
    func setHistory(_ value: PracticeHistory) { history = value }
    private var pauseRecord = false
    private var continuation: CheckedContinuation<Void, Never>?
    private var observer: CheckedContinuation<Void, Never>?
    func pauseNextRecord() { pauseRecord = true }
    func waitForRecord() async {
        if continuation != nil { return }
        await withCheckedContinuation { observer = $0 }
    }
    func resumeRecord() { continuation?.resume(); continuation = nil }
    func record(_ answer: AnswerFact) async throws(PersistenceError) {
        if pauseRecord {
            pauseRecord = false
            await withCheckedContinuation { continuation = $0; observer?.resume(); observer = nil }
        }
        if recordFails { throw .saveFailed("test") }
        facts.append(answer)
    }
    func answers(examID: ExamID) throws(PersistenceError) -> [AnswerFact] { facts }
    func outcomes(examID: ExamID) throws(PersistenceError) -> [AnswerOutcome] { [] }
    func practiceHistory(examID: ExamID, now: Date) throws(PersistenceError) -> PracticeHistory { history }
    func markServed(questionIDs: [String], examID: ExamID, at date: Date) throws(PersistenceError) {
        if servedFails { throw .saveFailed("test") }; served = questionIDs
    }
    func setFlag(_ flagged: Bool, questionID: String, examID: ExamID, at date: Date) throws(PersistenceError) {
        if flagged { history.flagged.insert(questionID) } else { history.flagged.remove(questionID) }
    }
}
