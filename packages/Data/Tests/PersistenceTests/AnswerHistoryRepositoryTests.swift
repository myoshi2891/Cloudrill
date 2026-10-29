import Foundation
import SwiftData
import Testing
import DomainInterfaces
import StudyModels
@testable import Persistence

@MainActor struct AnswerHistoryRepositoryTests {
    @Test func lastResultAndReadinessIncludeEveryMode() async throws {
        let repo = SwiftDataAnswerHistoryRepository(modelContainer: try PersistenceFixtures.container())
        for (index, mode) in [StudyMode.practice, .practice, .exam, .exam, .exam, .drill].enumerated() {
            try await repo.record(PersistenceFixtures.answer(correct: index > 0, mode: mode, at: PersistenceFixtures.now.addingTimeInterval(Double(index))))
        }
        #expect(try await repo.answers(examID: "test-alpha").count == 6)
        let history = try await repo.practiceHistory(examID: "test-alpha", now: PersistenceFixtures.now)
        #expect(history.lastResult["Q1"] == true)
        #expect(try await repo.answers(examID: "test-beta").isEmpty == true)
    }
    @Test func servedFlagsAndResultsArePerExam() async throws {
        let repo = SwiftDataAnswerHistoryRepository(modelContainer: try PersistenceFixtures.container())
        try await repo.record(PersistenceFixtures.answer(correct: false))
        try await repo.record(PersistenceFixtures.answer(exam: "test-beta", correct: true))
        try await repo.markServed(questionIDs: ["Q1"], examID: "test-alpha", at: PersistenceFixtures.now.addingTimeInterval(-90000))
        try await repo.markServed(questionIDs: ["Q2"], examID: "test-alpha", at: PersistenceFixtures.now.addingTimeInterval(-3600))
        try await repo.setFlag(true, questionID: "Q1", examID: "test-alpha", at: PersistenceFixtures.now)
        try await repo.setFlag(true, questionID: "Q1", examID: "test-alpha", at: PersistenceFixtures.now)
        let alpha = try await repo.practiceHistory(examID: "test-alpha", now: PersistenceFixtures.now)
        let beta = try await repo.practiceHistory(examID: "test-beta", now: PersistenceFixtures.now)
        #expect(alpha.lastResult["Q1"] == false && beta.lastResult["Q1"] == true)
        #expect(alpha.lastServedAt.count == 2 && beta.lastServedAt.isEmpty)
        #expect(alpha.flagged == ["Q1"] && beta.flagged.isEmpty)
        try await repo.setFlag(false, questionID: "Q1", examID: "test-alpha", at: PersistenceFixtures.now)
        #expect(try await repo.practiceHistory(examID: "test-alpha", now: PersistenceFixtures.now).flagged.isEmpty == true)
    }
    @Test func flagUsesInjectedTime() async throws {
        let container = try PersistenceFixtures.container()
        let repo = SwiftDataAnswerHistoryRepository(modelContainer: container)
        let date = PersistenceFixtures.now.addingTimeInterval(-3600)
        try await repo.setFlag(true, questionID: "Q1", examID: "test-alpha", at: date)
        let rows = try ModelContext(container).fetch(FetchDescriptor<SchemaV1.Flag>())
        #expect(rows.map(\.createdAt) == [date])
    }
    @Test func rejectsUnknownStoredMode() async throws {
        let container = try PersistenceFixtures.container()
        let context = ModelContext(container)
        let row = SchemaV1.AnswerRecord(); row.examID = "test-alpha"; row.modeRaw = "future"
        context.insert(row); try context.save()
        let repo = SwiftDataAnswerHistoryRepository(modelContainer: container)
        await #expect(throws: PersistenceError.corrupted("unknown study mode")) { try await repo.answers(examID: "test-alpha") }
        await #expect(throws: PersistenceError.corrupted("unknown study mode")) {
            try await repo.practiceHistory(examID: "test-alpha", now: PersistenceFixtures.now)
        }
    }
}
