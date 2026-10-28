import Foundation
import SwiftData
import Testing
@testable import Persistence

private final class PausedSaver: Saver, Sendable {
    let entered = DispatchSemaphore(value: 0)
    let resume = DispatchSemaphore(value: 0)

    func save(_ context: ModelContext) throws {
        entered.signal()
        guard resume.wait(timeout: .now() + 10) == .success else {
            throw CocoaError(.fileWriteUnknown)
        }
        try context.save()
    }
}

struct WriteCoordinationTests {
    private func wait(_ semaphore: DispatchSemaphore, seconds: Double) async -> DispatchTimeoutResult {
        await withCheckedContinuation { continuation in
            DispatchQueue.global().async {
                continuation.resume(returning: semaphore.wait(timeout: .now() + seconds))
            }
        }
    }

    @Test(arguments: [false, true])
    func readOrDeletionWaitsForAnotherRepositoryToSave(delete: Bool) async throws {
        let container = try PersistenceFixtures.container()
        let saver = PausedSaver()
        let writer = Task.detached {
            let repository = SwiftDataExamAttemptRepository(modelContainer: container, saver: saver)
            return try await repository.start(examID: "test-alpha", examSet: 1, packVersion: "1.0.0",
                                              snapshot: PersistenceFixtures.snapshot())
        }
        defer { saver.resume.signal() }
        let entered = await wait(saver.entered, seconds: 5)
        try #require(entered == .success)
        let started = DispatchSemaphore(value: 0)
        let completed = DispatchSemaphore(value: 0)
        let operation = Task.detached {
            let repository = DataManagement(modelContainer: container)
            started.signal()
            defer { completed.signal() }
            if delete { try await repository.deleteAll(examID: "test-alpha") }
            return try await repository.export(examID: "test-alpha")
        }
        #expect(await wait(started, seconds: 5) == .success)
        let finishedEarly = await wait(completed, seconds: 0.2) == .success
        #expect(!finishedEarly, "Reads and deletion must wait for the outstanding repository save")
        saver.resume.signal()
        _ = try await writer.value
        let data = try await operation.value
        let document = try #require(JSONSerialization.jsonObject(with: data) as? [String: Any])
        let entities = try #require(document["entities"] as? [String: [[String: Any]]])
        #expect(entities["ExamAttempt"]?.count == (delete ? 0 : 1))
        #expect(entities.filter { $0.key != "ExamAttempt" }.values.allSatisfy { $0.isEmpty })
    }
}
