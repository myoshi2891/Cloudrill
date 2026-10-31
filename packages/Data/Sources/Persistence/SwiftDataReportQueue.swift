import Foundation
import SwiftData
import DomainModels
import DomainInterfaces

@ModelActor public actor SwiftDataReportQueue: ReportQueue {
    public func enqueue(_ entry: PendingReportEntry) throws(PersistenceError) {
        try Storage.write(modelContext, saver: ContextSaver()) {
            let row = ReportQueueSchemaV1.PendingReport()
            row.id = entry.id; row.examID = entry.examID.rawValue; row.questionID = entry.questionID
            row.questionRevision = entry.questionRevision; row.packVersion = entry.packVersion
            row.reasonRaw = entry.reason.rawValue; row.comment = entry.comment
            row.appVersion = entry.appVersion; row.locale = entry.locale; row.createdAt = entry.createdAt
            modelContext.insert(row)
        }
    }

    public func pending(examID: ExamID?) throws(PersistenceError) -> [PendingReportEntry] {
        try Storage.read {
            try rows(examID: examID).map { row in
                guard let reason = ReportReason(rawValue: row.reasonRaw) else { throw PersistenceError.corrupted("unknown report reason") }
                return PendingReportEntry(id: row.id, examID: ExamID(rawValue: row.examID), questionID: row.questionID,
                                          questionRevision: row.questionRevision, packVersion: row.packVersion, reason: reason,
                                          comment: row.comment, appVersion: row.appVersion, locale: row.locale, createdAt: row.createdAt)
            }.sorted { $0.createdAt == $1.createdAt ? $0.id.uuidString < $1.id.uuidString : $0.createdAt < $1.createdAt }
        }
    }

    public func remove(ids: Set<UUID>) throws(PersistenceError) {
        guard !ids.isEmpty else { return }
        try Storage.write(modelContext, saver: ContextSaver()) {
            for row in try rows(examID: nil) where ids.contains(row.id) { modelContext.delete(row) }
        }
    }

    public func removeAll(examID: ExamID?) throws(PersistenceError) {
        try Storage.write(modelContext, saver: ContextSaver()) {
            for row in try rows(examID: examID) { modelContext.delete(row) }
        }
    }

    private func rows(examID: ExamID?) throws -> [ReportQueueSchemaV1.PendingReport] {
        guard let exam = examID?.rawValue else { return try modelContext.fetch(FetchDescriptor<ReportQueueSchemaV1.PendingReport>()) }
        return try modelContext.fetch(FetchDescriptor<ReportQueueSchemaV1.PendingReport>(predicate: #Predicate { $0.examID == exam }))
    }
}
