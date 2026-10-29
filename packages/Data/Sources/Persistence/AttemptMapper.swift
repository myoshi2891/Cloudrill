import Foundation
import DomainModels
import DomainInterfaces
import StudyModels
import ExamEngine

enum AttemptStatus: String { case inProgress, submitted, abandoned }
enum AttemptMapper {
    static func status(_ row: SchemaV1.ExamAttempt) throws -> AttemptStatus {
        guard let status = AttemptStatus(rawValue: row.statusRaw) else { throw PersistenceError.corrupted("unknown attempt status") }
        return status
    }
    static func snapshot(_ row: SchemaV1.ExamAttempt) throws -> AttemptSnapshot {
        _ = try status(row)
        return AttemptSnapshot(id: row.id, examID: ExamID(rawValue: row.examID), examSet: row.examSet,
                               packVersion: row.packVersion, startedAt: row.startedAt,
                               snapshot: try Storage.decode(ExamSession.Snapshot.self, row.sessionSnapshotJSON))
    }
    static func summary(_ row: SchemaV1.ExamAttempt) throws -> AttemptSummary {
        guard let submitted = row.submittedAt, let raw = row.submitReasonRaw, let reason = SubmitReason(rawValue: raw) else {
            throw PersistenceError.corrupted("invalid submitted attempt")
        }
        return AttemptSummary(attempt: try snapshot(row), submittedAt: submitted, reason: reason,
                              total: .init(correct: row.correctCount, total: row.totalCount))
    }
}
enum AnswerMapper {
    static func record(_ answer: AnswerFact) throws -> SchemaV1.AnswerRecord {
        let row = SchemaV1.AnswerRecord()
        row.examID = answer.examID.rawValue; row.questionID = answer.questionID
        row.questionRevision = answer.questionRevision; row.domain = answer.domain; row.subObjective = answer.subObjective
        row.caseStudy = answer.caseStudy?.rawValue; row.selectionJSON = try Storage.encode(answer.selection)
        row.isCorrect = answer.isCorrect; row.modeRaw = answer.mode.rawValue
        row.elapsedSeconds = answer.elapsedSeconds; row.answeredAt = answer.answeredAt
        return row
    }
    static func fact(_ row: SchemaV1.AnswerRecord) throws -> AnswerFact {
        guard let mode = StudyMode(rawValue: row.modeRaw) else { throw PersistenceError.corrupted("unknown study mode") }
        return AnswerFact(examID: ExamID(rawValue: row.examID), questionID: row.questionID, questionRevision: row.questionRevision,
                          domain: row.domain, subObjective: row.subObjective, caseStudy: row.caseStudy.map(CaseStudyID.init(rawValue:)),
                          selection: try Storage.decode(AnswerSelection.self, row.selectionJSON), isCorrect: row.isCorrect,
                          mode: mode, answeredAt: row.answeredAt, elapsedSeconds: row.elapsedSeconds)
    }
}
