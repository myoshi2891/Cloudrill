import Foundation
import SwiftData
import Testing
import DomainModels
import DomainInterfaces
@testable import Persistence

@MainActor struct ReportQueueTests {
    private func entry(_ question: String, exam: String = "test-alpha", at offset: TimeInterval = 0) -> PendingReportEntry {
        PendingReportEntry(id: UUID(), examID: ExamID(rawValue: exam), questionID: question, questionRevision: 2, packVersion: "1.2.0",
                           reason: .wrongAnswer, comment: "C が正しいのでは", appVersion: "1.0.3", locale: "ja-JP",
                           createdAt: PersistenceFixtures.now.addingTimeInterval(offset))
    }

    @Test func queuePersists() async throws {
        // Arrange
        let root = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let report = entry("Q1")
        do {
            let queue = SwiftDataReportQueue(modelContainer: try ReportQueueContainerFactory.make(inMemory: false, storeDirectory: root))
            try await queue.enqueue(report)
        }
        // Act
        let reopened = SwiftDataReportQueue(modelContainer: try ReportQueueContainerFactory.make(inMemory: false, storeDirectory: root))
        // Assert
        #expect(try await reopened.pending(examID: nil) == [report])
        #expect(FileManager.default.fileExists(atPath: root.appending(path: "ReportQueue.store").path()))
    }

    @Test func pendingIsOldestFirstAndFiltersByExam() async throws {
        let queue = SwiftDataReportQueue(modelContainer: try ReportQueueContainerFactory.make(inMemory: true))
        let late = entry("Q2", at: 60), early = entry("Q1"), beta = entry("Q9", exam: "test-beta", at: 30)
        for item in [late, early, beta] { try await queue.enqueue(item) }
        #expect(try await queue.pending(examID: nil).map(\.questionID) == ["Q1", "Q9", "Q2"])
        #expect(try await queue.pending(examID: "test-alpha").map(\.questionID) == ["Q1", "Q2"])
    }

    @Test func removeDeletesOnlyGivenIDs() async throws {
        let queue = SwiftDataReportQueue(modelContainer: try ReportQueueContainerFactory.make(inMemory: true))
        let first = entry("Q1"), second = entry("Q2", at: 1)
        for item in [first, second] { try await queue.enqueue(item) }
        try await queue.remove(ids: [first.id])
        #expect(try await queue.pending(examID: nil) == [second])
    }

    @Test func removeAllRespectsExam() async throws {
        let queue = SwiftDataReportQueue(modelContainer: try ReportQueueContainerFactory.make(inMemory: true))
        let beta = entry("Q9", exam: "test-beta")
        for item in [entry("Q1"), beta] { try await queue.enqueue(item) }
        try await queue.removeAll(examID: "test-alpha")
        #expect(try await queue.pending(examID: nil) == [beta])
        try await queue.removeAll(examID: nil)
        #expect(try await queue.pending(examID: nil).isEmpty)
    }

    @Test func unknownReasonIsCorrupted() async throws {
        let container = try ReportQueueContainerFactory.make(inMemory: true)
        let context = ModelContext(container)
        let row = ReportQueueSchemaV1.PendingReport(); row.examID = "test-alpha"; row.reasonRaw = "future"
        context.insert(row); try context.save()
        let queue = SwiftDataReportQueue(modelContainer: container)
        await #expect(throws: PersistenceError.corrupted("unknown report reason")) { try await queue.pending(examID: nil) }
    }

    @Test func containerIsLocalOnlyWithPlan() throws {
        let root = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let container = try ReportQueueContainerFactory.make(inMemory: false, storeDirectory: root)
        let plan = try #require(container.migrationPlan)
        #expect(ObjectIdentifier(plan) == ObjectIdentifier(ReportQueueMigrationPlan.self))
        #expect(container.configurations.allSatisfy { $0.cloudKitContainerIdentifier == nil })
        #expect(container.configurations.map(\.url.lastPathComponent) == ["ReportQueue.store"])
        #expect(throws: ModelContainerFactoryError.storeDirectoryRequired) { try ReportQueueContainerFactory.make(inMemory: false) }
    }
}
