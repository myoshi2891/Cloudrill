import Foundation
import DomainModels
public enum BookmarkTarget: String, Codable, Sendable { case question, doc }
public struct BookmarkEntry: Hashable, Sendable {
    public var id: UUID
    public var targetType: BookmarkTarget
    public var targetID: String
    public var createdAt: Date
    public init(id: UUID, targetType: BookmarkTarget, targetID: String, createdAt: Date) {
        self.id = id; self.targetType = targetType; self.targetID = targetID; self.createdAt = createdAt
    }
}
public protocol BookmarkRepository: Sendable {
    func toggleBookmark(targetType: BookmarkTarget, targetID: String, examID: ExamID, at date: Date) async throws(PersistenceError) -> Bool
    func bookmarks(examID: ExamID, type: BookmarkTarget?) async throws(PersistenceError) -> [BookmarkEntry]
    func markRead(_ subObjective: String, examID: ExamID, at date: Date) async throws(PersistenceError)
    func isRead(_ subObjective: String, examID: ExamID) async throws(PersistenceError) -> Bool
}
