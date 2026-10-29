import Foundation
import Testing
import AppCore
import ExamFeature
import DomainModels
import DomainInterfaces
import StudyModels
import ExamEngine
import DomainTestSupport
import Synchronization
import FSRS

@MainActor struct ExamSessionViewModelTests {
    @Test func loadsAllQuestionsOnceAndRestoresOrder() async throws {
        let h = try SessionHarness(count: 55)
        await h.model.load()
        #expect(h.content.reads.withLock { $0 } == 1)
        #expect(h.model.state.totalCount == 55)
        #expect(h.model.state.question?.choices.map(\.id) == ["d", "c", "b", "a"])
        await h.model.move(to: 54)
        await h.model.move(to: 0)
        #expect(h.content.reads.withLock { $0 } == 1)
        #expect(QuestionRendererRegistry.standard.supportedKinds == Set(QuestionKind.allCases))
    }
    @Test func selectionPersistsAndDoesNotExposeCorrectness() async throws {
        let h = try SessionHarness()
        await h.model.load()
        await h.model.select(choiceID: "a")
        #expect(h.model.state.selected == ["a"])
        #expect(await h.attempts.records.count == 1)
        #expect(await h.attempts.current?.snapshot.answers["Q0"] == .choices(["a"]))
        #expect(await h.attempts.saves == 1)
        let question = try #require(h.model.state.question)
        #expect(!Mirror(reflecting: question).children.contains { $0.label == "correctChoiceIDs" })
        #expect(!Mirror(reflecting: question.choices[0]).children.contains { $0.label == "isCorrect" })
        await h.model.select(choiceID: "b")
        #expect(h.model.state.selected == ["b"])
    }
    @Test func multipleLimitAndDeselection() async throws {
        let h = try SessionHarness(multiple: true)
        await h.model.load()
        #expect(h.model.state.question?.requiredSelections == 2)
        await h.model.select(choiceID: "a")
        await h.model.select(choiceID: "b")
        await h.model.select(choiceID: "c")
        #expect(h.model.state.selected == ["a", "b"])
        #expect(h.model.state.alert == "session.selectionLimit")
        #expect(await h.attempts.records.count == 2)
        await h.model.select(choiceID: "a")
        await h.model.select(choiceID: "b")
        #expect(h.model.state.selected.isEmpty)
        #expect(await h.attempts.current?.snapshot.answers["Q0"] == nil)
    }
    @Test func flagMoveAndSnapshotRestoration() async throws {
        let h = try SessionHarness(count: 2)
        await h.model.load()
        await h.model.move(to: 1)
        await h.model.select(choiceID: "c")
        await h.model.toggleFlag()
        await h.model.scenePhaseChanged(isActive: false)
        let restored = h.newModel()
        h.time.advance(by: .seconds(61))
        await restored.load()
        #expect(restored.state.currentIndex == 1)
        #expect(restored.state.isFlagged)
        #expect(restored.state.selected == ["c"])
        #expect(restored.state.remainingSeconds == 3539)
        #expect(restored.state.sessionState == .inProgress)
    }
    @Test func warningThresholdsOnlyRequestFeedbackOnce() async throws {
        let h = try SessionHarness(duration: 601)
        await h.model.load()
        h.time.advance(by: .seconds(2))
        await h.model.tick()
        #expect(h.model.state.warning == .tenMinutes)
        #expect(h.model.state.feedbackCount == 1)
        await h.model.tick()
        #expect(h.model.state.feedbackCount == 1)
        h.time.advance(by: .seconds(300))
        await h.model.tick()
        #expect(h.model.state.warning == .fiveMinutes)
        #expect(h.model.state.feedbackCount == 2)
    }
    @Test func expiryFinalizesOnceAndUnpins() async throws {
        let h = try SessionHarness(duration: 60)
        await h.model.load()
        await h.model.select(choiceID: "a")
        h.time.advance(by: .seconds(61))
        await h.model.tick()
        await h.model.tick()
        #expect(await h.attempts.finalizations == 1)
        #expect(await h.attempts.result?.total == ScoreTally(correct: 1, total: 1))
        #expect(await h.attempts.reason == .timeExpired)
        #expect(await h.pins.pinned == nil)
        #expect(h.router.path(for: .exam) == [.examResult(attemptID: h.id)])
    }
    @Test func backgroundContinuesTimeAndExpiredResumeSubmits() async throws {
        let h = try SessionHarness(duration: 60)
        await h.model.load()
        await h.model.scenePhaseChanged(isActive: false)
        #expect(await h.attempts.current?.snapshot.state == .suspended)
        h.time.advance(by: .seconds(61))
        await h.model.scenePhaseChanged(isActive: true)
        #expect(h.model.state.sessionState == .submitted(.timeExpired))
        #expect(h.router.path(for: .exam).last == .examResult(attemptID: h.id))
    }
    @Test func caseSheetOnlyForCaseQuestions() async throws {
        let h = try SessionHarness(count: 2, caseQuestion: true)
        await h.model.load()
        #expect(h.model.state.caseStudy?.id == "A")
        await h.model.move(to: 1)
        #expect(h.model.state.caseStudy == nil)
    }
    @Test func usesPinnedVersionEvenWhenActiveContentChanged() async throws {
        let h = try SessionHarness()
        await h.model.load()
        #expect(h.resolver.requests.withLock { $0 } == ["1.0.0"])
        #expect(h.model.state.question?.stem == "Version 1.0.0")
    }
    @Test func missingPinnedVersionDoesNotOpenCurrentContent() async throws {
        let h = try SessionHarness()
        h.resolver.fails.withLock { $0 = true }
        await h.model.load()
        #expect(h.model.state.question == nil)
        #expect(h.model.state.alert == "session.loadFailed")
        #expect(h.content.reads.withLock { $0 } == 0)
    }
    @Test func recordFailureKeepsSelectionAndCanRetry() async throws {
        let h = try SessionHarness()
        await h.model.load()
        await h.attempts.failRecord(true)
        await h.model.select(choiceID: "a")
        #expect(h.model.state.selected.isEmpty)
        #expect(h.model.state.alert == "session.saveFailed")
        await h.attempts.failRecord(false)
        await h.model.select(choiceID: "a")
        #expect(h.model.state.selected == ["a"])
    }
    @Test func snapshotFailureAfterRecordKeepsCommittedAnswer() async throws {
        let h = try SessionHarness()
        await h.model.load()
        await h.attempts.failSave(true)
        await h.model.select(choiceID: "a")
        #expect(h.model.state.selected == ["a"])
        #expect(await h.attempts.current?.snapshot.answers["Q0"] == .choices(["a"]))
        #expect(h.model.state.alert == "session.saveFailed")
    }
    @Test func finalizeAndUnpinFailuresAreRetryable() async throws {
        let h = try SessionHarness(duration: 1)
        await h.model.load()
        await h.attempts.failFinalize(true)
        h.time.advance(by: .seconds(2))
        await h.model.tick()
        #expect(h.router.path(for: .exam).isEmpty)
        await h.attempts.failFinalize(false)
        await h.pins.failUnpin(true)
        await h.model.tick()
        #expect(await h.attempts.finalizations == 1)
        #expect(h.router.path(for: .exam).isEmpty)
        await h.pins.failUnpin(false)
        await h.model.tick()
        #expect(await h.attempts.finalizations == 1)
        #expect(h.router.path(for: .exam) == [.examResult(attemptID: h.id)])
    }
    @Test func backgroundDuringSaveIsNotDroppedAndDuplicateSelectionIsIgnored() async throws {
        let h = try SessionHarness()
        await h.model.load()
        await h.attempts.pauseNextRecord()
        let selecting = Task { await h.model.select(choiceID: "a") }
        await h.attempts.waitForRecord()
        await h.model.select(choiceID: "b")
        await h.model.scenePhaseChanged(isActive: false)
        await h.attempts.resumeRecord()
        await selecting.value
        #expect(await h.attempts.records.count == 1)
        #expect(await h.attempts.current?.snapshot.answers["Q0"] == .choices(["a"]))
        #expect(await h.attempts.current?.snapshot.state == .suspended)
        await h.model.scenePhaseChanged(isActive: true)
        #expect(h.model.state.selected == ["a"])
        #expect(h.model.state.sessionState == .inProgress)
    }

    @Test func expiredSelectionIsNotRecorded() async throws {
        let h = try SessionHarness(duration: 1)
        await h.model.load()
        h.time.advance(by: .seconds(2))
        await h.model.select(choiceID: "a")
        #expect(await h.attempts.records.isEmpty)
        #expect(await h.attempts.reason == .timeExpired)
    }
}

@MainActor struct SessionHarness {
    let id = UUID()
    let time = ManualTimeSource(SelectionFixtures.now)
    let content: SessionContent
    let resolver: SessionResolver
    let attempts: SessionAttempts
    let pins = TestPins()
    let cards = SessionCards()
    let settings = SessionPreferences()
    let router = AppRouter()
    var model: ExamSessionViewModel!
    init(count: Int = 1, multiple: Bool = false, duration: Int = 3600, caseQuestion: Bool = false, flashcardsEnabled: Bool = true) throws {
        var base = try ExamFixture("test-alpha")
        base.definition.features.flashcards = flashcardsEnabled
        let questions = (0..<count).map { index in
            (multiple ? QuestionBuilder.multiple(count: 2, correct: ["a", "b"]) : .single())
                .with(\.id, "Q\(index)").with(\.stem, LocalizedText(ja: "Version 1.0.0"))
                .with(\.caseStudy, caseQuestion && index == 0 ? "A" : nil).build()
        }
        content = SessionContent(base: base, values: questions)
        resolver = SessionResolver(content: content)
        let order = QuestionOrder(items: questions.map { .init(questionID: $0.id, choiceIDs: $0.choices.map(\.id).reversed()) })
        var session = ExamSession(order: order, duration: .seconds(duration), timerPolicy: .init())
        try session.handle(.start, at: SelectionFixtures.now)
        attempts = SessionAttempts(AttemptSnapshot(id: id, examID: "test-alpha", examSet: 1,
            packVersion: "1.0.0", startedAt: SelectionFixtures.now, snapshot: session.snapshot))
        model = newModel()
    }
    func newModel() -> ExamSessionViewModel {
        ExamSessionViewModel(examID: "test-alpha", attemptID: id, contentResolver: resolver,
            attempts: attempts, pins: pins, cards: cards, settings: settings, time: time, router: router)
    }
}
final class SessionContent: ExamContentProvider, Sendable {
    let base: ExamFixture
    let values: [Question]
    let reads = Mutex(0)
    init(base: ExamFixture, values: [Question]) { self.base = base; self.values = values }
    var definition: ExamDefinition { base.definition }
    var vendor: Vendor { base.vendor }
    var packVersion: String { "1.0.0" }
    var questionIndex: [QuestionIndexEntry] { [] }
    var examSets: [ExamSet] { base.examSets }
    var docsIndex: [DocEntry] { [] }
    func questions(ids: [String]) async throws(ContentError) -> [Question] { reads.withLock { $0 += 1 }; return values }
    func caseStudies() async throws(ContentError) -> [CaseStudy] { try await base.caseStudies() }
    func flashcards() async throws(ContentError) -> [Flashcard] { [] }
    func decisionTrees() async throws(ContentError) -> [DecisionTree] { [] }
    func keywordDrills() async throws(ContentError) -> [KeywordDrill] { [] }
    func docBody(for entry: DocEntry) async throws(ContentError) -> String { "" }
}
final class SessionResolver: ExamContentResolving, Sendable {
    let content: SessionContent
    let requests = Mutex<[String]>([])
    let fails = Mutex(false)
    init(content: SessionContent) { self.content = content }
    func content(for examID: ExamID, version: String) async throws(ContentError) -> any ExamContentProvider {
        requests.withLock { $0.append(version) }
        if fails.withLock({ $0 }) { throw .fileMissing(version) }
        return content
    }
}
actor SessionAttempts: ExamAttemptRepository {
    var current: AttemptSnapshot?
    var records: [AnswerFact] = []
    var saves = 0
    var finalizations = 0
    var result: ExamResult?
    var reason: SubmitReason?
    var recordFails = false, saveFails = false, finalizeFails = false
    var pauseRecord = false
    var recordContinuation: CheckedContinuation<Void, Never>?
    var waitContinuation: CheckedContinuation<Void, Never>?
    func pauseNextRecord() { pauseRecord = true }
    func waitForRecord() async {
        if recordContinuation != nil { return }
        await withCheckedContinuation { waitContinuation = $0 }
    }
    func resumeRecord() { recordContinuation?.resume(); recordContinuation = nil }

    init(_ current: AttemptSnapshot) { self.current = current }
    func failRecord(_ value: Bool) { recordFails = value }
    func failSave(_ value: Bool) { saveFails = value }
    func failFinalize(_ value: Bool) { finalizeFails = value }
    func inProgress(examID: ExamID) throws(PersistenceError) -> AttemptSnapshot? { current }
    func record(_ answer: AnswerFact, in attemptID: UUID) async throws(PersistenceError) {
        if pauseRecord {
            pauseRecord = false
            await withCheckedContinuation { continuation in
                recordContinuation = continuation
                waitContinuation?.resume(); waitContinuation = nil
            }
        }
        if recordFails { throw .saveFailed("test") }
        records.append(answer)
        if case .choices(let ids) = answer.selection { current?.snapshot.answers[answer.questionID] = ids.isEmpty ? nil : answer.selection }
    }
    func save(snapshot: ExamSession.Snapshot, for attemptID: UUID) throws(PersistenceError) {
        if saveFails { throw .saveFailed("test") }; saves += 1; current?.snapshot = snapshot
    }
    func finalize(attemptID: UUID, result: ExamResult, reason: SubmitReason, at date: Date) throws(PersistenceError) {
        if finalizeFails { throw .saveFailed("test") }
        finalizations += 1; self.result = result; self.reason = reason; current = nil
    }
    func start(examID: ExamID, examSet: Int, packVersion: String, snapshot: ExamSession.Snapshot) throws(PersistenceError) -> UUID { UUID() }
    func abandon(attemptID: UUID) throws(PersistenceError) { current = nil }
    func history(examID: ExamID) throws(PersistenceError) -> [AttemptSummary] { [] }
}

actor SessionCards: CardStateRepository {
    var added: [String] = []
    var failingID: String?
    func fail(on id: String?) { failingID = id }
    func card(id: String, examID: ExamID) throws(PersistenceError) -> FSRSCard? { nil }
    func apply(_ outcome: ReviewOutcome, cardID: String, examID: ExamID) throws(PersistenceError) {}
    func scheduledCards(examID: ExamID) throws(PersistenceError) -> [(id: String, card: FSRSCard)] { [] }
    func reviewCount(examID: ExamID, on day: DateInterval) throws(PersistenceError) -> (introduced: Int, reviewed: Int) { (0, 0) }
    func addCardFromQuestion(questionID: String, examID: ExamID, at date: Date) throws(PersistenceError) {
        if questionID == failingID { throw .saveFailed("test") }
        added.append(questionID)
    }
}
actor SessionPreferences: SettingsRepository {
    var autoCards = true
    var fails = false
    func setAutoCards(_ value: Bool) { autoCards = value }
    func fail(_ value: Bool) { fails = value }
    func settings() throws(PersistenceError) -> UserSettings { UserSettings() }
    func preference(examID: ExamID) throws(PersistenceError) -> ExamPreference {
        if fails { throw .saveFailed("test") }
        var value = ExamPreference.default; value.autoCardFromMistakes = autoCards; return value
    }
    func save(settings: UserSettings, at date: Date) throws(PersistenceError) {}
    func save(preference: ExamPreference, examID: ExamID, at date: Date) throws(PersistenceError) {}
}
