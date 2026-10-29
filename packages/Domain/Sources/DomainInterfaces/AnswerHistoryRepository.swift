import Foundation
import DomainModels
import StudyModels
import QuestionSelector

public protocol AnswerHistoryRepository: Sendable {
    func record(_ answer: AnswerFact) async throws(PersistenceError)
    func answers(examID: ExamID) async throws(PersistenceError) -> [AnswerFact]
    /// 集計専用。選択内容を復号しないため、未知の選択形式の行があっても失敗しない。
    func outcomes(examID: ExamID) async throws(PersistenceError) -> [AnswerOutcome]
    func practiceHistory(examID: ExamID, now: Date) async throws(PersistenceError) -> PracticeHistory
    func markServed(questionIDs: [String], examID: ExamID, at date: Date) async throws(PersistenceError)
    func setFlag(_ flagged: Bool, questionID: String, examID: ExamID, at date: Date) async throws(PersistenceError)
}
