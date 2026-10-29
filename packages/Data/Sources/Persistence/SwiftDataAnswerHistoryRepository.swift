import Foundation
import SwiftData
import DomainModels
import DomainInterfaces
import StudyModels
import QuestionSelector

@ModelActor public actor SwiftDataAnswerHistoryRepository: AnswerHistoryRepository {
    public func record(_ answer: AnswerFact) throws(PersistenceError) {
        try Storage.write(modelContext, saver: ContextSaver()) { modelContext.insert(try AnswerMapper.record(answer)) }
    }
    private func records(_ examID: ExamID) throws -> [SchemaV1.AnswerRecord] {
        let exam = examID.rawValue
        return try modelContext.fetch(FetchDescriptor<SchemaV1.AnswerRecord>(predicate: #Predicate { $0.examID == exam })).sorted {
            $0.answeredAt == $1.answeredAt ? $0.id.uuidString < $1.id.uuidString : $0.answeredAt < $1.answeredAt
        }
    }
    public func answers(examID: ExamID) throws(PersistenceError) -> [AnswerFact] {
        try Storage.read { try records(examID).map(AnswerMapper.fact) }
    }
    public func practiceHistory(examID: ExamID, now: Date) throws(PersistenceError) -> PracticeHistory {
        try Storage.read {
            let exam = examID.rawValue
            var history = PracticeHistory()
            // 使わない選択内容は復号しない。
            for row in try records(examID) {
                guard StudyMode(rawValue: row.modeRaw) != nil else { throw PersistenceError.corrupted("unknown study mode") }
                history.lastResult[row.questionID] = row.isCorrect
            }
            history.flagged = Set(try modelContext.fetch(FetchDescriptor<SchemaV1.Flag>(predicate: #Predicate { $0.examID == exam })).map(\.questionID))
            for row in try modelContext.fetch(FetchDescriptor<SchemaV1.PracticeServeLog>(predicate: #Predicate { $0.examID == exam })) {
                history.lastServedAt[row.questionID] = max(history.lastServedAt[row.questionID] ?? .distantPast, row.servedAt)
            }
            return history
        }
    }
    public func markServed(questionIDs: [String], examID: ExamID, at date: Date) throws(PersistenceError) {
        try Storage.write(modelContext, saver: ContextSaver()) {
            for id in Set(questionIDs).sorted() {
                let row = SchemaV1.PracticeServeLog(); row.examID = examID.rawValue; row.questionID = id; row.servedAt = date
                modelContext.insert(row)
            }
        }
    }
    public func setFlag(_ flagged: Bool, questionID: String, examID: ExamID, at date: Date) throws(PersistenceError) {
        try Storage.write(modelContext, saver: ContextSaver()) {
            let exam = examID.rawValue
            let rows = try modelContext.fetch(FetchDescriptor<SchemaV1.Flag>(predicate: #Predicate { $0.examID == exam && $0.questionID == questionID }))
            if flagged && rows.isEmpty {
                let row = SchemaV1.Flag(); row.examID = exam; row.questionID = questionID; row.createdAt = date
                modelContext.insert(row)
            } else if !flagged { for row in rows { modelContext.delete(row) } }
        }
    }
}
