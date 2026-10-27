import Foundation
import SwiftData
import DomainModels
import DomainInterfaces
import StudyModels
import ExamEngine

@ModelActor public actor SwiftDataExamAttemptRepository: ExamAttemptRepository {
    private var saver: any Saver = ContextSaver()
    public init(modelContainer: ModelContainer, saver: any Saver) {
        self.modelContainer = modelContainer
        self.modelExecutor = DefaultSerialModelExecutor(modelContext: ModelContext(modelContainer))
        self.saver = saver
    }
    public func start(examID: ExamID, examSet: Int, packVersion: String, snapshot: ExamSession.Snapshot) throws(PersistenceError) -> UUID { UUID() }
    public func save(snapshot: ExamSession.Snapshot, for attemptID: UUID) throws(PersistenceError) {}
    public func record(_ answer: AnswerFact, in attemptID: UUID) throws(PersistenceError) {}
    public func finalize(attemptID: UUID, result: ExamResult, reason: SubmitReason, at date: Date) throws(PersistenceError) {}
    public func abandon(attemptID: UUID) throws(PersistenceError) {}
    public func inProgress(examID: ExamID) throws(PersistenceError) -> AttemptSnapshot? { nil }
    public func history(examID: ExamID) throws(PersistenceError) -> [AttemptSummary] { [] }
}
