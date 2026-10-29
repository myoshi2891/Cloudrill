import Foundation
import SwiftData
import DomainModels
import DomainInterfaces
@ModelActor public actor SwiftDataBookmarkRepository: BookmarkRepository {
    public func toggleBookmark(targetType: BookmarkTarget, targetID: String, examID: ExamID, at date: Date) throws(PersistenceError) -> Bool {
        try Storage.write(modelContext, saver: ContextSaver()) {
            let exam = examID.rawValue, type = targetType.rawValue
            let rows = try modelContext.fetch(FetchDescriptor<SchemaV1.Bookmark>(predicate: #Predicate {
                $0.examID == exam && $0.targetType == type && $0.targetID == targetID
            }))
            if rows.isEmpty {
                let row = SchemaV1.Bookmark(); row.examID = exam; row.targetType = type; row.targetID = targetID; row.createdAt = date
                modelContext.insert(row); return true
            }
            for row in rows { modelContext.delete(row) }
            return false
        }
    }
    public func bookmarks(examID: ExamID, type: BookmarkTarget?) throws(PersistenceError) -> [BookmarkEntry] {
        try Storage.read {
            let exam = examID.rawValue
            return try modelContext.fetch(FetchDescriptor<SchemaV1.Bookmark>(predicate: #Predicate { $0.examID == exam })).map { row in
                guard let target = BookmarkTarget(rawValue: row.targetType) else { throw PersistenceError.corrupted("unknown bookmark target") }
                return BookmarkEntry(id: row.id, targetType: target, targetID: row.targetID, createdAt: row.createdAt)
            }.filter { type == nil || $0.targetType == type }.sorted {
                $0.createdAt == $1.createdAt ? $0.id.uuidString < $1.id.uuidString : $0.createdAt > $1.createdAt
            }
        }
    }
    public func markRead(_ subObjective: String, examID: ExamID, at date: Date) throws(PersistenceError) {
        try Storage.write(modelContext, saver: ContextSaver()) {
            guard try !isRead(subObjective, examID: examID) else { return }
            let row = SchemaV1.ReadMark(); row.examID = examID.rawValue; row.docSubObjective = subObjective; row.readAt = date
            modelContext.insert(row)
        }
    }
    public func isRead(_ subObjective: String, examID: ExamID) throws(PersistenceError) -> Bool {
        try Storage.read {
            let exam = examID.rawValue
            return try modelContext.fetchCount(FetchDescriptor<SchemaV1.ReadMark>(predicate: #Predicate {
                $0.examID == exam && $0.docSubObjective == subObjective
            })) > 0
        }
    }
}
