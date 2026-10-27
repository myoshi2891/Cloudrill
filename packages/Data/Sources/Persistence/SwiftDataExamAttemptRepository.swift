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
    private func active(_ id: UUID) throws -> SchemaV1.ExamAttempt {
        // UUID を受け取る API は、開始時に返した受験そのものを参照する。
        let rows = try modelContext.fetch(FetchDescriptor<SchemaV1.ExamAttempt>(predicate: #Predicate { $0.id == id }))
        guard let row = rows.first else { throw PersistenceError.notFound }
        guard rows.count == 1, try AttemptMapper.status(row) == .inProgress else { throw PersistenceError.corrupted("attempt is not in progress") }
        return row
    }
    public func start(examID: ExamID, examSet: Int, packVersion: String, snapshot: ExamSession.Snapshot) throws(PersistenceError) -> UUID {
        try Storage.write(modelContext, saver: saver) {
            guard let timer = snapshot.timer, [.inProgress, .reviewing, .suspended].contains(snapshot.state) else {
                throw PersistenceError.corrupted("invalid initial snapshot")
            }
            let row = SchemaV1.ExamAttempt()
            row.examID = examID.rawValue; row.examSet = examSet; row.packVersion = packVersion
            row.startedAt = timer.deadline.addingTimeInterval(-snapshot.duration.timeInterval)
            row.sessionSnapshotJSON = try Storage.encode(snapshot)
            modelContext.insert(row)
            return row.id
        }
    }
    public func save(snapshot: ExamSession.Snapshot, for attemptID: UUID) throws(PersistenceError) {
        try Storage.write(modelContext, saver: saver) {
            let row = try active(attemptID)
            guard snapshot.timer != nil, [.inProgress, .reviewing, .suspended].contains(snapshot.state) else { throw PersistenceError.corrupted("invalid active snapshot") }
            row.sessionSnapshotJSON = try Storage.encode(snapshot)
        }
    }
    public func record(_ answer: AnswerFact, in attemptID: UUID) throws(PersistenceError) {
        try Storage.write(modelContext, saver: saver) {
            let attempt = try active(attemptID)
            let snapshot = try AttemptMapper.snapshot(attempt).snapshot
            guard answer.examID.rawValue == attempt.examID, answer.mode == .exam,
                  snapshot.order.items.contains(where: { $0.questionID == answer.questionID }) else {
                throw PersistenceError.corrupted("answer does not belong to attempt")
            }
            let row = try AnswerMapper.record(answer)
            modelContext.insert(row); row.attempt = attempt
        }
    }
    public func finalize(attemptID: UUID, result: ExamResult, reason: SubmitReason, at date: Date) throws(PersistenceError) {
        try Storage.write(modelContext, saver: saver) {
            let row = try active(attemptID)
            var snapshot = try AttemptMapper.snapshot(row).snapshot
            snapshot.state = .submitted(reason)
            row.sessionSnapshotJSON = try Storage.encode(snapshot)
            row.statusRaw = AttemptStatus.submitted.rawValue; row.submitReasonRaw = reason.rawValue; row.submittedAt = date
            row.correctCount = result.total.correct; row.totalCount = result.total.total
        }
    }
    public func abandon(attemptID: UUID) throws(PersistenceError) {
        try Storage.write(modelContext, saver: saver) {
            let row = try active(attemptID)
            var snapshot = try AttemptMapper.snapshot(row).snapshot
            snapshot.state = .abandoned
            row.sessionSnapshotJSON = try Storage.encode(snapshot); row.statusRaw = AttemptStatus.abandoned.rawValue
        }
    }
    private func attempts(_ examID: ExamID) throws -> [SchemaV1.ExamAttempt] {
        let exam = examID.rawValue
        let rows = try modelContext.fetch(FetchDescriptor<SchemaV1.ExamAttempt>(predicate: #Predicate { $0.examID == exam }))
        for row in rows { _ = try AttemptMapper.status(row) }
        return rows
    }
    public func inProgress(examID: ExamID) throws(PersistenceError) -> AttemptSnapshot? {
        try Storage.read {
            try attempts(examID).filter { $0.statusRaw == "inProgress" }.sorted {
                $0.startedAt == $1.startedAt ? $0.id.uuidString < $1.id.uuidString : $0.startedAt > $1.startedAt
            }.first.map(AttemptMapper.snapshot)
        }
    }
    public func history(examID: ExamID) throws(PersistenceError) -> [AttemptSummary] {
        try Storage.read {
            try attempts(examID).filter { $0.statusRaw == "submitted" }.map(AttemptMapper.summary).sorted {
                $0.submittedAt == $1.submittedAt ? $0.id.uuidString < $1.id.uuidString : $0.submittedAt > $1.submittedAt
            }
        }
    }
}
