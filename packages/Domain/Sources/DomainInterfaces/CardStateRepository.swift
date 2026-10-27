import Foundation
import DomainModels
import FSRS
public protocol CardStateRepository: Sendable {
    func card(id: String, examID: ExamID) async throws(PersistenceError) -> FSRSCard?
    func apply(_ outcome: ReviewOutcome, cardID: String, examID: ExamID) async throws(PersistenceError)
    func scheduledCards(examID: ExamID) async throws(PersistenceError) -> [(id: String, card: FSRSCard)]
    func reviewCount(examID: ExamID, on day: DateInterval) async throws(PersistenceError) -> (introduced: Int, reviewed: Int)
    func addCardFromQuestion(questionID: String, examID: ExamID, at date: Date) async throws(PersistenceError)
}
