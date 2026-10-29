import Foundation
import SwiftData
import DomainModels
import DomainInterfaces
import FSRS
@ModelActor public actor SwiftDataCardStateRepository: CardStateRepository {
    private func states(_ examID: ExamID) throws -> [SchemaV1.CardState] {
        let exam = examID.rawValue
        return try modelContext.fetch(FetchDescriptor<SchemaV1.CardState>(predicate: #Predicate { $0.examID == exam })).sorted {
            let left = $0.lastReview ?? .distantPast, right = $1.lastReview ?? .distantPast
            return left == right ? $0.id.uuidString < $1.id.uuidString : left > right
        }
    }
    private func state(cardID: String, examID: ExamID) throws -> SchemaV1.CardState? {
        let exam = examID.rawValue
        return try modelContext.fetch(FetchDescriptor<SchemaV1.CardState>(predicate: #Predicate {
            $0.examID == exam && $0.cardID == cardID
        })).sorted {
            let left = $0.lastReview ?? .distantPast, right = $1.lastReview ?? .distantPast
            return left == right ? $0.id.uuidString < $1.id.uuidString : left > right
        }.first
    }
    public func card(id: String, examID: ExamID) throws(PersistenceError) -> FSRSCard? {
        try Storage.read { try state(cardID: id, examID: examID).map { try Storage.decode(FSRSCard.self, $0.fsrsCardJSON) } }
    }
    public func apply(_ outcome: ReviewOutcome, cardID: String, examID: ExamID) throws(PersistenceError) {
        try Storage.write(modelContext, saver: ContextSaver()) {
            let row = try state(cardID: cardID, examID: examID) ?? SchemaV1.CardState()
            row.examID = examID.rawValue; row.cardID = cardID
            row.fsrsCardJSON = try Storage.encode(outcome.card); row.due = outcome.card.due; row.lastReview = outcome.card.lastReview
            modelContext.insert(row)
            let log = SchemaV1.ReviewLog(); log.examID = examID.rawValue; log.cardID = cardID
            log.rating = outcome.rating.rawValue; log.elapsedDays = outcome.elapsedDays; log.reviewedAt = outcome.reviewedAt
            modelContext.insert(log); log.cardState = row
        }
    }
    public func scheduledCards(examID: ExamID) throws(PersistenceError) -> [(id: String, card: FSRSCard)] {
        try Storage.read {
            var seen: Set<String> = []
            return try states(examID).filter { seen.insert($0.cardID).inserted }.map {
                (id: $0.cardID, card: try Storage.decode(FSRSCard.self, $0.fsrsCardJSON))
            }.sorted { $0.card.due == $1.card.due ? $0.id < $1.id : $0.card.due < $1.card.due }
        }
    }
    public func reviewCount(examID: ExamID, on day: DateInterval) throws(PersistenceError) -> (introduced: Int, reviewed: Int) {
        try Storage.read {
            let exam = examID.rawValue
            let logs = try modelContext.fetch(FetchDescriptor<SchemaV1.ReviewLog>(predicate: #Predicate { $0.examID == exam })).sorted {
                $0.reviewedAt == $1.reviewedAt ? $0.id.uuidString < $1.id.uuidString : $0.reviewedAt < $1.reviewedAt
            }
            var seen: Set<String> = []; var introduced = 0; var reviewed = 0
            for log in logs {
                guard Rating(rawValue: log.rating) != nil else { throw PersistenceError.corrupted("unknown review rating") }
                let first = seen.insert(log.cardID).inserted
                if log.reviewedAt >= day.start && log.reviewedAt < day.end {
                    if first { introduced += 1 } else { reviewed += 1 }
                }
            }
            return (introduced, reviewed)
        }
    }
    public func addCardFromQuestion(questionID: String, examID: ExamID, at date: Date) throws(PersistenceError) {
        try Storage.write(modelContext, saver: ContextSaver()) {
            let id = "Q:" + questionID
            guard try state(cardID: id, examID: examID) == nil else { return }
            let row = SchemaV1.CardState(); row.examID = examID.rawValue; row.cardID = id
            row.fsrsCardJSON = try Storage.encode(FSRSCard.new(at: date)); row.due = date
            modelContext.insert(row)
        }
    }
}
