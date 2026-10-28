import Foundation
import SwiftData
import Testing
import FSRS
@testable import Persistence

@MainActor struct CardStateRepositoryTests {
    @Test func singleCardLookupAndApplyPreserveOtherCardsAndExams() async throws {
        let container = try PersistenceFixtures.container()
        let context = ModelContext(container)
        let now = PersistenceFixtures.now
        var rows: [SchemaV1.CardState] = []
        for (exam, cardID, offset) in [("test-alpha", "C1", 0.0), ("test-alpha", "C1", 60.0),
                                       ("test-alpha", "C2", 120.0), ("test-beta", "C1", 180.0)] {
            let row = SchemaV1.CardState()
            row.examID = exam; row.cardID = cardID
            row.lastReview = now.addingTimeInterval(offset)
            row.fsrsCardJSON = try Storage.encode(FSRSCard.new(at: now.addingTimeInterval(offset)))
            context.insert(row); rows.append(row)
        }
        try context.save()
        let original = rows.map(\.fsrsCardJSON)
        let repo = SwiftDataCardStateRepository(modelContainer: container)
        #expect(try await repo.card(id: "C1", examID: "test-alpha") == .new(at: now.addingTimeInterval(60)))
        let outcome = FSRSScheduler(parameters: try .init()).review(.new(at: now), rating: .good, at: now.addingTimeInterval(300))
        try await repo.apply(outcome, cardID: "C1", examID: "test-alpha")
        let saved = try ModelContext(container).fetch(FetchDescriptor<SchemaV1.CardState>())
        #expect(saved.count == 4)
        for index in rows.indices {
            let row = try #require(saved.first { $0.id == rows[index].id })
            #expect(row.fsrsCardJSON == (index == 1 ? try Storage.encode(outcome.card) : original[index]))
        }
    }
    @Test func applyRoundTripsAndAppendsLogs() async throws {
        let container = try PersistenceFixtures.container()
        let repo = SwiftDataCardStateRepository(modelContainer: container)
        let scheduler = FSRSScheduler(parameters: try .init())
        let first = scheduler.review(.new(at: PersistenceFixtures.now), rating: .good, at: PersistenceFixtures.now)
        try await repo.apply(first, cardID: "C1", examID: "test-alpha")
        #expect(try await repo.card(id: "C1", examID: "test-alpha") == first.card)
        let second = scheduler.review(first.card, rating: .good, at: PersistenceFixtures.now.addingTimeInterval(600))
        try await repo.apply(second, cardID: "C1", examID: "test-alpha")
        #expect(try await repo.card(id: "C1", examID: "test-alpha") == second.card)
        #expect(try await repo.card(id: "C1", examID: "test-beta") == nil)
        let context = ModelContext(container)
        let rows = try context.fetch(FetchDescriptor<SchemaV1.CardState>())
        #expect(rows.count == 1 && rows.first?.due == second.card.due)
        let logs = try context.fetch(FetchDescriptor<SchemaV1.ReviewLog>())
        #expect(logs.count == 2 && logs.allSatisfy { $0.cardState?.cardID == "C1" })
        #expect(try await repo.scheduledCards(examID: "test-alpha").map(\.id) == ["C1"])
    }
    @Test func questionCardIsIdempotentAndPerExam() async throws {
        let repo = SwiftDataCardStateRepository(modelContainer: try PersistenceFixtures.container())
        for _ in 0..<2 { try await repo.addCardFromQuestion(questionID: "Q1", examID: "test-alpha", at: PersistenceFixtures.now) }
        #expect(try await repo.scheduledCards(examID: "test-alpha").count == 1)
        #expect(try await repo.card(id: "Q:Q1", examID: "test-alpha") == .new(at: PersistenceFixtures.now))
        #expect(try await repo.scheduledCards(examID: "test-beta").isEmpty == true)
    }
    @Test func reviewCountUsesHalfOpenDayAndFirstEverReview() async throws {
        let repo = SwiftDataCardStateRepository(modelContainer: try PersistenceFixtures.container())
        let scheduler = FSRSScheduler(parameters: try .init())
        let now = PersistenceFixtures.now
        // 昨日の新規2件は今日の新規には含めない。
        for id in ["old1", "old2"] {
            try await repo.apply(scheduler.review(.new(at: now), rating: .good, at: now.addingTimeInterval(-3600)), cardID: id, examID: "test-alpha")
        }
        for id in ["new1", "new2", "new3"] {
            try await repo.apply(scheduler.review(.new(at: now), rating: .good, at: now), cardID: id, examID: "test-alpha")
        }
        for i in 0..<5 {
            let card = try #require(await repo.card(id: "old1", examID: "test-alpha"))
            try await repo.apply(scheduler.review(card, rating: .good, at: now.addingTimeInterval(Double(i + 1) * 60)), cardID: "old1", examID: "test-alpha")
        }
        try await repo.apply(scheduler.review(.new(at: now), rating: .good, at: now.addingTimeInterval(86400)), cardID: "tomorrow", examID: "test-alpha")
        let count = try await repo.reviewCount(examID: "test-alpha", on: DateInterval(start: now, duration: 86400))
        #expect(count.introduced == 3 && count.reviewed == 5)
        let other = try await repo.reviewCount(examID: "test-beta", on: DateInterval(start: now, duration: 86400))
        #expect(other.introduced == 0 && other.reviewed == 0)
    }
}
