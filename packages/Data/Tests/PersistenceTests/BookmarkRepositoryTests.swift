import Foundation
import SwiftData
import Testing
import DomainInterfaces
@testable import Persistence
@MainActor struct BookmarkRepositoryTests {
    @Test func togglesAndFiltersByTypeAndExam() async throws {
        let repo = SwiftDataBookmarkRepository(modelContainer: try PersistenceFixtures.container())
        for id in ["Q1", "Q2"] { #expect(try await repo.toggleBookmark(targetType: .question, targetID: id, examID: "test-alpha", at: PersistenceFixtures.now)) }
        _ = try await repo.toggleBookmark(targetType: .doc, targetID: "3.2", examID: "test-alpha", at: PersistenceFixtures.now)
        #expect(try await repo.bookmarks(examID: "test-alpha", type: .question).count == 2)
        #expect(try await repo.bookmarks(examID: "test-alpha", type: .doc).map(\.targetID) == ["3.2"])
        #expect(try await repo.bookmarks(examID: "test-beta", type: nil).isEmpty == true)
        #expect(try await !repo.toggleBookmark(targetType: .question, targetID: "Q1", examID: "test-alpha", at: PersistenceFixtures.now))
        #expect(try await repo.bookmarks(examID: "test-alpha", type: .question).map(\.targetID) == ["Q2"])
    }
    @Test func readMarksAreIdempotentAndIsolated() async throws {
        let container = try PersistenceFixtures.container()
        let repo = SwiftDataBookmarkRepository(modelContainer: container)
        for _ in 0..<2 { try await repo.markRead("3.2", examID: "test-alpha", at: PersistenceFixtures.now) }
        #expect(try await repo.isRead("3.2", examID: "test-alpha"))
        #expect(try await !repo.isRead("3.2", examID: "test-beta"))
        #expect(try ModelContext(container).fetchCount(FetchDescriptor<SchemaV1.ReadMark>()) == 1)
    }
    @Test func unknownTargetTypeIsCorrupted() async throws {
        let container = try PersistenceFixtures.container(), context: ModelContext
        context = ModelContext(container)
        let row = SchemaV1.Bookmark(); row.examID = "test-alpha"; row.targetType = "future"
        context.insert(row); try context.save()
        let repo = SwiftDataBookmarkRepository(modelContainer: container)
        await #expect(throws: PersistenceError.corrupted("unknown bookmark target")) { try await repo.bookmarks(examID: "test-alpha", type: nil) }
    }
}
