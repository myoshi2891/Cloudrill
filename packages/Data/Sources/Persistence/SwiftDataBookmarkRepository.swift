import Foundation
import SwiftData
import DomainModels
import DomainInterfaces
@ModelActor public actor SwiftDataBookmarkRepository: BookmarkRepository {
    public func toggleBookmark(targetType: BookmarkTarget, targetID: String, examID: ExamID, at date: Date) throws(PersistenceError) -> Bool { false }
    public func bookmarks(examID: ExamID, type: BookmarkTarget?) throws(PersistenceError) -> [BookmarkEntry] { [] }
    public func markRead(_ subObjective: String, examID: ExamID, at date: Date) throws(PersistenceError) {}
    public func isRead(_ subObjective: String, examID: ExamID) throws(PersistenceError) -> Bool { false }
}
