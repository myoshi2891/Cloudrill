import Foundation
import SwiftData
import Testing
import DomainModels
import DomainInterfaces
import StudyModels
import ExamEngine
@testable import Persistence

enum PersistenceFixtures {
    static let now = Date(timeIntervalSince1970: 1_800_000_000)
    static func container() throws -> ModelContainer { try ModelContainerFactory.make(inMemory: true, cloudKitContainer: nil) }
    static func snapshot() throws -> ExamSession.Snapshot {
        var session = ExamSession(order: QuestionOrder(items: [
            .init(questionID: "Q1", choiceIDs: ["a", "b"]), .init(questionID: "Q2", choiceIDs: ["c", "d"]),
        ]), duration: .seconds(3600), timerPolicy: .init())
        try session.handle(.start, at: now)
        try session.select(.choices(["a"]), for: "Q1")
        try session.toggleFlag(for: "Q2")
        try session.move(to: 1)
        try session.handle(.suspend, at: now.addingTimeInterval(30))
        return session.snapshot
    }
    static func answer(exam: ExamID = "test-alpha", id: String = "Q1", correct: Bool = true, mode: StudyMode = .exam, at: Date = now) -> AnswerFact {
        AnswerFact(examID: exam, questionID: id, questionRevision: 2, domain: 1, subObjective: "1.1", caseStudy: nil,
                   selection: .choices(["a"]), isCorrect: correct, mode: mode, answeredAt: at, elapsedSeconds: 5)
    }
    static let result = ExamResult(total: .init(correct: 1, total: 2), byDomain: [:], byCaseStudy: [:], unansweredCount: 0)
}

final class FailingSaver: Saver, @unchecked Sendable {
    private let lock = NSLock()
    private var calls = 0
    let failures: Int
    init(failures: Int) { self.failures = failures }
    var count: Int { lock.withLock { calls } }
    func save(_ context: ModelContext) throws {
        let fail = lock.withLock { calls += 1; return calls <= failures }
        if fail { throw CocoaError(.fileWriteUnknown) }
        try context.save()
    }
}

@MainActor struct ExamAttemptRepositoryTests {
    @Test func startAndFindInProgressAndRoundTrip() async throws {
        let repo = SwiftDataExamAttemptRepository(modelContainer: try PersistenceFixtures.container())
        let snapshot = try PersistenceFixtures.snapshot()
        let id = try await repo.start(examID: "test-alpha", examSet: 1, packVersion: "1.0.0", snapshot: snapshot)
        let found = try #require(await repo.inProgress(examID: "test-alpha"))
        #expect(found.id == id && found.packVersion == "1.0.0" && found.snapshot == snapshot)
        #expect(found.startedAt == PersistenceFixtures.now)
        #expect(try await repo.inProgress(examID: "test-beta") == nil)
        var changed = snapshot
        changed.currentIndex = 0
        try await repo.save(snapshot: changed, for: id)
        #expect(try await repo.inProgress(examID: "test-alpha")?.snapshot == changed)
    }
    @Test(arguments: [ExamSessionState.inProgress, .reviewing, .suspended])
    func saveRejectsActiveSnapshotWithoutTimer(state: ExamSessionState) async throws {
        let repo = SwiftDataExamAttemptRepository(modelContainer: try PersistenceFixtures.container())
        let snapshot = try PersistenceFixtures.snapshot()
        let id = try await repo.start(examID: "test-alpha", examSet: 1, packVersion: "1.0.0", snapshot: snapshot)
        var invalid = snapshot
        invalid.state = state
        invalid.timer = nil
        await #expect(throws: PersistenceError.corrupted("invalid active snapshot")) {
            try await repo.save(snapshot: invalid, for: id)
        }
        #expect(try await repo.inProgress(examID: "test-alpha")?.snapshot == snapshot)
    }
    @Test func recordEachAnswerAndFinalize() async throws {
        let container = try PersistenceFixtures.container()
        let repo = SwiftDataExamAttemptRepository(modelContainer: container)
        let id = try await repo.start(examID: "test-alpha", examSet: 1, packVersion: "1.0.0", snapshot: PersistenceFixtures.snapshot())
        for _ in 0..<3 { try await repo.record(PersistenceFixtures.answer(), in: id) }
        let records = try ModelContext(container).fetch(FetchDescriptor<SchemaV1.AnswerRecord>())
        #expect(records.count == 3)
        #expect(records.allSatisfy { $0.modeRaw == "exam" && $0.attempt?.id == id })
        try await repo.finalize(attemptID: id, result: PersistenceFixtures.result, reason: .user, at: PersistenceFixtures.now)
        #expect(try await repo.inProgress(examID: "test-alpha") == nil)
        let history = try await repo.history(examID: "test-alpha")
        #expect(history.first?.total == .init(correct: 1, total: 2))
        #expect(history.first?.reason == .user)
        await #expect(throws: PersistenceError.corrupted("attempt is not in progress")) {
            try await repo.finalize(attemptID: id, result: PersistenceFixtures.result, reason: .user, at: PersistenceFixtures.now)
        }
    }
    @Test func historyOmitsAbandonedAndOtherExams() async throws {
        let repo = SwiftDataExamAttemptRepository(modelContainer: try PersistenceFixtures.container())
        var ids: [UUID] = []
        for offset in 0..<3 {
            let id = try await repo.start(examID: "test-alpha", examSet: offset + 1, packVersion: "1.0.0", snapshot: PersistenceFixtures.snapshot())
            ids.append(id)
            if offset == 2 { try await repo.abandon(attemptID: id) }
            else { try await repo.finalize(attemptID: id, result: PersistenceFixtures.result, reason: .timeExpired, at: PersistenceFixtures.now.addingTimeInterval(Double(offset))) }
        }
        #expect(try await repo.history(examID: "test-alpha").map(\.id) == [ids[1], ids[0]])
        #expect(try await repo.history(examID: "test-beta").isEmpty == true)
    }
    @Test func recordSurvivesNewContainer() async throws {
        let root = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let snapshot = try PersistenceFixtures.snapshot()
        do {
            let container = try ModelContainerFactory.make(inMemory: false, cloudKitContainer: nil, storeDirectory: root)
            let repo = SwiftDataExamAttemptRepository(modelContainer: container)
            let id = try await repo.start(examID: "test-alpha", examSet: 1, packVersion: "1.0.0", snapshot: snapshot)
            try await repo.record(PersistenceFixtures.answer(), in: id)
        }
        let reopened = try ModelContainerFactory.make(inMemory: false, cloudKitContainer: nil, storeDirectory: root)
        let repo = SwiftDataExamAttemptRepository(modelContainer: reopened)
        #expect(try await repo.inProgress(examID: "test-alpha")?.snapshot == snapshot)
        #expect(try ModelContext(reopened).fetchCount(FetchDescriptor<SchemaV1.AnswerRecord>()) == 1)
    }
    @Test(arguments: [1, 2]) func saveRetriesAndRollsBack(failures: Int) async throws {
        let container = try PersistenceFixtures.container()
        let saver = FailingSaver(failures: failures)
        let repo = SwiftDataExamAttemptRepository(modelContainer: container, saver: saver)
        if failures == 1 {
            _ = try await repo.start(examID: "test-alpha", examSet: 1, packVersion: "1.0.0", snapshot: PersistenceFixtures.snapshot())
            #expect(try await repo.inProgress(examID: "test-alpha") != nil)
        } else {
            do {
                _ = try await repo.start(examID: "test-alpha", examSet: 1, packVersion: "1.0.0", snapshot: PersistenceFixtures.snapshot())
                Issue.record("Expected start to throw PersistenceError.saveFailed")
            } catch PersistenceError.saveFailed {
            } catch {
                Issue.record("Expected PersistenceError.saveFailed, got \(error)")
            }
            #expect(try await repo.inProgress(examID: "test-alpha") == nil)
        }
        #expect(saver.count == 2)
        #expect(try ModelContext(container).fetchCount(FetchDescriptor<SchemaV1.ExamAttempt>()) == (failures == 1 ? 1 : 0))
    }
    @Test func rejectsWrongExamAndMissingAttempt() async throws {
        let repo = SwiftDataExamAttemptRepository(modelContainer: try PersistenceFixtures.container())
        let id = try await repo.start(examID: "test-alpha", examSet: 1, packVersion: "1.0.0", snapshot: PersistenceFixtures.snapshot())
        await #expect(throws: PersistenceError.corrupted("answer does not belong to attempt")) {
            try await repo.record(PersistenceFixtures.answer(exam: "test-beta"), in: id)
        }
        await #expect(throws: PersistenceError.notFound) { try await repo.abandon(attemptID: UUID()) }
    }
}
