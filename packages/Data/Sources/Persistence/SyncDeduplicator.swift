import Foundation
import SwiftData
import DomainInterfaces
import ExamEngine
@ModelActor public actor SyncDeduplicator {
    public func run() throws(PersistenceError) -> SyncMerge.Plan {
        try Storage.write(modelContext, saver: ContextSaver()) {
            let rows = try PersistenceRows(context: modelContext)
            // 全スナップショットを読んでから変更する。壊れた入力なら何も削除しない。
            var records = try rows.examAttempts.map { row in
                let status = try AttemptMapper.status(row)
                let progress = status == .inProgress ? try AttemptMapper.snapshot(row).snapshot.currentIndex : nil
                return SyncMerge.Record(id: row.id, kind: .examAttempt, examID: row.examID, target: [String(row.examSet)], progress: progress)
            }
            records += rows.cardStates.map { .init(id: $0.id, kind: .cardState, examID: $0.examID, target: [$0.cardID], date: $0.lastReview) }
            records += rows.examPreferences.map { .init(id: $0.id, kind: .examPreference, examID: $0.examID, date: $0.updatedAt) }
            records += rows.userSettings.map { .init(id: $0.id, kind: .userSettings, examID: "", date: $0.updatedAt) }
            records += rows.flags.map { .init(id: $0.id, kind: .flag, examID: $0.examID, target: [$0.questionID], date: $0.createdAt) }
            records += rows.bookmarks.map { .init(id: $0.id, kind: .bookmark, examID: $0.examID, target: [$0.targetType, $0.targetID], date: $0.createdAt) }
            records += rows.readMarks.map { .init(id: $0.id, kind: .readMark, examID: $0.examID, target: [$0.docSubObjective], date: $0.readAt) }
            records += rows.answerRecords.map { .init(id: $0.id, kind: .answerRecord, examID: $0.examID) }
            records += rows.reviewLogs.map { .init(id: $0.id, kind: .reviewLog, examID: $0.examID) }
            records += rows.practiceServeLogs.map { .init(id: $0.id, kind: .practiceServeLog, examID: $0.examID) }
            let plan = SyncMerge.resolve(records)
            let deleted = Set(plan.deleted), abandoned = Set(plan.abandoned)
            for row in rows.examAttempts where abandoned.contains(row.id) {
                var snapshot = try AttemptMapper.snapshot(row).snapshot
                snapshot.state = .abandoned
                row.sessionSnapshotJSON = try Storage.encode(snapshot); row.statusRaw = AttemptStatus.abandoned.rawValue
            }
            let keptStates = rows.cardStates.filter { !deleted.contains($0.id) }
            for row in rows.cardStates where deleted.contains(row.id) {
                guard let kept = keptStates.first(where: { $0.examID == row.examID && $0.cardID == row.cardID }) else {
                    throw PersistenceError.corrupted("missing retained card state")
                }
                for log in row.reviewLogs ?? [] { log.cardState = kept }
                modelContext.delete(row)
            }
            for row in rows.examPreferences where deleted.contains(row.id) { modelContext.delete(row) }
            for row in rows.userSettings where deleted.contains(row.id) { modelContext.delete(row) }
            for row in rows.flags where deleted.contains(row.id) { modelContext.delete(row) }
            for row in rows.bookmarks where deleted.contains(row.id) { modelContext.delete(row) }
            for row in rows.readMarks where deleted.contains(row.id) { modelContext.delete(row) }
            return plan
        }
    }
}
