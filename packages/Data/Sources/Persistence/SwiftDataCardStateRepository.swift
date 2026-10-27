import Foundation
import SwiftData
import DomainModels
import DomainInterfaces
import FSRS
@ModelActor public actor SwiftDataCardStateRepository: CardStateRepository {
    public func card(id: String, examID: ExamID) throws(PersistenceError) -> FSRSCard? { nil }
    public func apply(_ outcome: ReviewOutcome, cardID: String, examID: ExamID) throws(PersistenceError) {}
    public func scheduledCards(examID: ExamID) throws(PersistenceError) -> [(id: String, card: FSRSCard)] { [] }
    public func reviewCount(examID: ExamID, on day: DateInterval) throws(PersistenceError) -> (introduced: Int, reviewed: Int) { (0, 0) }
    public func addCardFromQuestion(questionID: String, examID: ExamID, at date: Date) throws(PersistenceError) {}
}
