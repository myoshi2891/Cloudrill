import Foundation
import DomainModels
import StudyModels
import ExamEngine

// Snapshot が ExamEngine を参照するため、StudyModels の循環依存を避けてここに置く。
public struct AttemptSnapshot: Hashable, Sendable {
    public var id: UUID
    public var examID: ExamID
    public var examSet: Int
    public var packVersion: String
    public var startedAt: Date
    public var snapshot: ExamSession.Snapshot
    public init(id: UUID, examID: ExamID, examSet: Int, packVersion: String, startedAt: Date, snapshot: ExamSession.Snapshot) {
        self.id = id; self.examID = examID; self.examSet = examSet; self.packVersion = packVersion
        self.startedAt = startedAt; self.snapshot = snapshot
    }
}
public struct AttemptSummary: Hashable, Sendable {
    public var attempt: AttemptSnapshot
    public var submittedAt: Date
    public var reason: SubmitReason
    public var total: ScoreTally
    public var id: UUID { attempt.id }
    public init(attempt: AttemptSnapshot, submittedAt: Date, reason: SubmitReason, total: ScoreTally) {
        self.attempt = attempt; self.submittedAt = submittedAt; self.reason = reason; self.total = total
    }
}
public protocol ExamAttemptRepository: Sendable {
    func start(examID: ExamID, examSet: Int, packVersion: String, snapshot: ExamSession.Snapshot) async throws(PersistenceError) -> UUID
    func save(snapshot: ExamSession.Snapshot, for attemptID: UUID) async throws(PersistenceError)
    /// Atomically saves answer history and its selection in the persisted session snapshot.
    /// Other snapshot fields are preserved; use save(snapshot:for:) for navigation or lifecycle changes.
    func record(_ answer: AnswerFact, in attemptID: UUID) async throws(PersistenceError)
    func finalize(attemptID: UUID, result: ExamResult, reason: SubmitReason, at date: Date) async throws(PersistenceError)
    func abandon(attemptID: UUID) async throws(PersistenceError)
    func inProgress(examID: ExamID) async throws(PersistenceError) -> AttemptSnapshot?
    func history(examID: ExamID) async throws(PersistenceError) -> [AttemptSummary]
}
