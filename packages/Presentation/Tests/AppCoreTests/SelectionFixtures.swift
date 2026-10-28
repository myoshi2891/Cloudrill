import Foundation
import DomainModels
import DomainInterfaces
import StudyModels
import ExamEngine
import DomainTestSupport

enum SelectionFixtures {
    static let now = Date(timeIntervalSince1970: 1_800_000_000)
    static func content(_ id: ExamID) throws -> StubContent {
        let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent()
            .appending(path: "../../../../content/tests/fixtures/valid-json")
        let definition = try JSONDecoder().decode(ExamDefinition.self, from: Data(contentsOf: root.appending(path: "exams/\(id.rawValue)/exam.json")))
        let vendors = try JSONDecoder().decode(VendorsFile.self, from: Data(contentsOf: root.appending(path: "vendors.json")))
        guard let vendor = vendors.vendors.first(where: { $0.id == definition.vendor }) else { throw CocoaError(.fileReadCorruptFile) }
        return StubContent(definition: definition, vendor: vendor)
    }
    static func entry(_ id: ExamID, status: CatalogStatus = .available) throws -> CatalogEntry {
        let json = """
        {"id":"\(id.rawValue)","vendor":"\(id == "test-alpha" ? "google-cloud" : "example-cloud")","name":{"ja":"試験"},"shortName":"TEST",
         "status":"\(status.rawValue)","latestPackVersion":"1.0.0","minAppVersion":"1.0.0","productIDs":[]}
        """
        return try JSONDecoder().decode(CatalogEntry.self, from: Data(json.utf8))
    }
    static func attempt() throws -> AttemptSnapshot {
        var session = ExamSession(order: QuestionOrder(items: [.init(questionID: "Q1", choiceIDs: ["a", "b"])]),
                                  duration: .seconds(3600), timerPolicy: .init())
        try session.handle(.start, at: now)
        return AttemptSnapshot(id: UUID(), examID: "test-alpha", examSet: 1, packVersion: "1.0.0", startedAt: now, snapshot: session.snapshot)
    }
}

struct StubContent: ExamContentProvider {
    let definition: ExamDefinition
    let vendor: Vendor
    let packVersion = "1.0.0"
    let questionIndex: [QuestionIndexEntry] = []
    let examSets: [ExamSet] = []
    let docsIndex: [DocEntry] = []
    func questions(ids: [String]) async throws(ContentError) -> [Question] { [] }
    func flashcards() async throws(ContentError) -> [Flashcard] { [] }
    func caseStudies() async throws(ContentError) -> [CaseStudy] { [] }
    func decisionTrees() async throws(ContentError) -> [DecisionTree] { [] }
    func keywordDrills() async throws(ContentError) -> [KeywordDrill] { [] }
    func docBody(for entry: DocEntry) async throws(ContentError) -> String { "" }
}

actor SelectionSettings: SettingsRepository {
    var value: UserSettings
    var failSave = false
    var savedAt: Date?
    private var pauseRead = false
    private var pendingRead: CheckedContinuation<Void, Never>?
    private var readObserver: CheckedContinuation<Void, Never>?
    init(current: ExamID? = nil) { value = UserSettings(currentExamID: current, displayLanguage: .en, shuffleChoices: true) }
    func rejectSaves() { failSave = true }
    func pauseNextRead() { pauseRead = true }
    func waitForPausedRead() async {
        if pendingRead != nil { return }
        await withCheckedContinuation { readObserver = $0 }
    }
    func resumeRead() { pendingRead?.resume(); pendingRead = nil }
    func settings() async throws(PersistenceError) -> UserSettings {
        if pauseRead {
            pauseRead = false
            await withCheckedContinuation {
                pendingRead = $0
                readObserver?.resume(); readObserver = nil
            }
        }
        return value
    }
    func preference(examID: ExamID) throws(PersistenceError) -> ExamPreference { .default }
    func save(settings: UserSettings, at date: Date) throws(PersistenceError) {
        if failSave { throw .saveFailed("test") }
        value = settings; savedAt = date
    }
    func save(preference: ExamPreference, examID: ExamID, at date: Date) throws(PersistenceError) {}
}

actor SelectionAttempts: ExamAttemptRepository {
    var current: AttemptSnapshot?
    var failSave = false
    init(_ current: AttemptSnapshot? = nil) { self.current = current }
    func rejectSaves() { failSave = true }
    func inProgress(examID: ExamID) throws(PersistenceError) -> AttemptSnapshot? { current?.examID == examID ? current : nil }
    func save(snapshot: ExamSession.Snapshot, for attemptID: UUID) throws(PersistenceError) {
        if failSave { throw .saveFailed("test") }
        current?.snapshot = snapshot
    }
    func start(examID: ExamID, examSet: Int, packVersion: String, snapshot: ExamSession.Snapshot) throws(PersistenceError) -> UUID { throw .notFound }
    func record(_ answer: AnswerFact, in attemptID: UUID) throws(PersistenceError) {}
    func finalize(attemptID: UUID, result: ExamResult, reason: SubmitReason, at date: Date) throws(PersistenceError) {}
    func abandon(attemptID: UUID) throws(PersistenceError) {}
    func history(examID: ExamID) throws(PersistenceError) -> [AttemptSummary] { [] }
}
