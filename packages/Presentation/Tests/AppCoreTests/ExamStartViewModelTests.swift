import Foundation
import Testing
import AppCore
import ExamFeature
import DomainModels
import DomainInterfaces
import StudyModels
import ExamEngine
import DomainTestSupport

@MainActor struct ExamStartViewModelTests {
    @Test func listsCompleteExamSetsAndRespectsLimit() throws {
        var content = try ExamFixture("test-beta")
        var draft = content.examSets[0]; draft.id = 2; draft.status = .draft
        var outside = draft; outside.id = 3; outside.status = .complete
        content.examSets += [draft, outside]
        let model = ExamTopViewModel(content: content)
        #expect(model.sets.map(\.id) == [1])
        #if DEBUG
        #expect(ExamTopViewModel(content: content, includesDrafts: true).sets.map(\.id) == [1, 2])
        #endif
    }
    @Test func startShowsFormatAndCases() async throws {
        let beta = try harness("test-beta")
        await beta.model.load()
        #expect(beta.model.questionCount == 40)
        #expect(beta.model.durationMinutes == 90)
        #expect(beta.model.cases.isEmpty)
        let alpha = try harness("test-alpha")
        await alpha.model.load()
        #expect(alpha.model.cases.map(\.name.ja) == ["ケース A", "ケース B"])
    }
    @Test func startCreatesAttemptAndPins() async throws {
        let h = try harness("test-beta")
        await h.model.start()
        let attempt = try #require(await h.attempts.current)
        #expect(attempt.snapshot.order.items.map(\.questionID) == ["Q1"])
        #expect(attempt.snapshot.timer?.deadline == SelectionFixtures.now.addingTimeInterval(5400))
        #expect(await h.pins.pinned == attempt.id)
        #expect(h.router.path(for: .exam) == [.examSession(attemptID: attempt.id)])
    }
    @Test func startBlockedResumeAndAbandon() async throws {
        let h = try harness("test-alpha")
        let existing = try SelectionFixtures.attempt()
        await h.attempts.set(existing)
        await h.model.start()
        #expect(h.model.inProgress?.id == existing.id)
        #expect(await h.attempts.starts == 0)
        await h.model.resume()
        #expect(await h.pins.pinned == existing.id)
        #expect(h.router.path(for: .exam).last == .examSession(attemptID: existing.id))
        await h.model.abandon()
        #expect(await h.attempts.current == nil)
        #expect(await h.pins.pinned == nil)
    }
    @Test func pinFailureDoesNotNavigateAndCanRetry() async throws {
        let h = try harness("test-beta")
        await h.pins.fail(true)
        await h.model.start()
        #expect(h.model.error != nil)
        #expect(h.router.path(for: .exam).isEmpty)
        #expect(await h.attempts.current != nil)
        await h.pins.fail(false)
        await h.model.resume()
        #expect(h.router.path(for: .exam).count == 1)
        #expect(await h.attempts.starts == 1)
    }
    @Test func duplicateStartWhileAwaitingSettingsIsIgnored() async throws {
        let h = try harness("test-beta")
        await h.settings.pauseNextRead()
        let first = Task { await h.model.start() }
        await h.settings.waitForPausedRead()
        await h.model.start()
        await h.settings.resumeRead()
        await first.value
        #expect(await h.attempts.starts == 1)
    }
    @Test func abandonFailureKeepsAttemptAndPin() async throws {
        let h = try harness("test-beta")
        await h.model.start()
        let id = try #require(await h.attempts.current?.id)
        await h.attempts.rejectAbandon(true)
        await h.model.abandon()
        #expect(h.model.error != nil)
        #expect(await h.attempts.current?.id == id)
        #expect(await h.pins.pinned == id)
    }
    @Test func unpinFailureCanRetryAfterReload() async throws {
        let h = try harness("test-beta")
        await h.model.start()
        await h.pins.failUnpin(true)
        await h.model.abandon()
        #expect(await h.attempts.current == nil)
        #expect(h.model.inProgress != nil)
        await h.model.load()
        #expect(h.model.inProgress != nil)
        await h.pins.failUnpin(false)
        await h.model.abandon()
        #expect(h.model.inProgress == nil)
        #expect(await h.pins.pinned == nil)
    }
    private func harness(_ id: ExamID) throws -> (model: ExamStartViewModel, attempts: StartAttempts, pins: TestPins, router: AppRouter, settings: SelectionSettings) {
        let attempts = StartAttempts(), pins = TestPins(), router = AppRouter(), settings = SelectionSettings()
        let model = ExamStartViewModel(content: try ExamFixture(id), examSet: 1, attempts: attempts,
            pins: pins, settings: settings, time: FixedTimeSource(SelectionFixtures.now), seedProvider: { 42 }, router: router)
        return (model, attempts, pins, router, settings)
    }
}

struct ExamFixture: ExamContentProvider {
    var definition: ExamDefinition
    var vendor: Vendor
    var packVersion = "1.0.0"
    var examSets: [ExamSet]
    var questionIndex: [QuestionIndexEntry] = []
    var docsIndex: [DocEntry] = []
    init(_ id: ExamID) throws {
        let base = try SelectionFixtures.content(id)
        definition = base.definition; vendor = base.vendor
        let cases = id == "test-alpha" ? "[\"A\",\"B\"]" : "[]"
        examSets = [try JSONDecoder().decode(ExamSet.self, from: Data("{\"id\":1,\"status\":\"complete\",\"level\":\"basic\",\"caseStudies\":\(cases),\"questionIDs\":[\"Q1\"]}".utf8))]
    }
    func questions(ids: [String]) async throws(ContentError) -> [Question] { ids.map { QuestionBuilder.single().with(\.id, $0).build() } }
    func caseStudies() async throws(ContentError) -> [CaseStudy] {
        try! ["A", "B"].map { id in
            try JSONDecoder().decode(CaseStudy.self, from: Data("{\"id\":\"\(id)\",\"name\":{\"ja\":\"ケース \(id)\"},\"summary\":{\"ja\":\"概要\"},\"businessRequirements\":[],\"technicalRequirements\":[],\"existingEnvironment\":{\"ja\":\"環境\"},\"officialURL\":\"https://example.com\",\"requirementMappings\":[]}".utf8))
        }
    }
    func flashcards() async throws(ContentError) -> [Flashcard] { [] }
    func decisionTrees() async throws(ContentError) -> [DecisionTree] { [] }
    func keywordDrills() async throws(ContentError) -> [KeywordDrill] { [] }
    func docBody(for entry: DocEntry) async throws(ContentError) -> String { "" }
}
actor TestPins: PackPinning {
    var pinned: UUID?
    var fails = false
    var unpinFails = false
    func failUnpin(_ value: Bool) { unpinFails = value }
    func fail(_ value: Bool) { fails = value }
    func pin(_ version: String, for examID: ExamID, attemptID: UUID) throws(ContentError) {
        if fails { throw .storage("test") }; pinned = attemptID
    }
    func unpin(attemptID: UUID, for examID: ExamID) throws(ContentError) { if unpinFails { throw .storage("test") }; pinned = nil }
}
actor StartAttempts: ExamAttemptRepository {
    var current: AttemptSnapshot?
    var starts = 0
    var abandonFails = false
    func rejectAbandon(_ value: Bool) { abandonFails = value }
    func set(_ attempt: AttemptSnapshot) { current = attempt }
    func start(examID: ExamID, examSet: Int, packVersion: String, snapshot: ExamSession.Snapshot) throws(PersistenceError) -> UUID {
        starts += 1
        let id = UUID()
        current = AttemptSnapshot(id: id, examID: examID, examSet: examSet, packVersion: packVersion, startedAt: SelectionFixtures.now, snapshot: snapshot)
        return id
    }
    func inProgress(examID: ExamID) throws(PersistenceError) -> AttemptSnapshot? { current }
    func abandon(attemptID: UUID) throws(PersistenceError) { if abandonFails { throw .saveFailed("test") }; current = nil }
    func save(snapshot: ExamSession.Snapshot, for attemptID: UUID) throws(PersistenceError) {}
    func record(_ answer: AnswerFact, in attemptID: UUID) throws(PersistenceError) {}
    func finalize(attemptID: UUID, result: ExamResult, reason: SubmitReason, at date: Date) throws(PersistenceError) {}
    func history(examID: ExamID) throws(PersistenceError) -> [AttemptSummary] { [] }
}
