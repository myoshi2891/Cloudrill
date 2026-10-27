import Foundation
import SwiftData
import DomainModels
import DomainInterfaces
import StudyModels
import QuestionSelector

@ModelActor public actor SwiftDataAnswerHistoryRepository: AnswerHistoryRepository {
    public func record(_ answer: AnswerFact) throws(PersistenceError) {}
    public func answers(examID: ExamID) throws(PersistenceError) -> [AnswerFact] { [] }
    public func practiceHistory(examID: ExamID, now: Date) throws(PersistenceError) -> PracticeHistory { .init() }
    public func markServed(questionIDs: [String], examID: ExamID, at date: Date) throws(PersistenceError) {}
    public func setFlag(_ flagged: Bool, questionID: String, examID: ExamID) throws(PersistenceError) {}
}
