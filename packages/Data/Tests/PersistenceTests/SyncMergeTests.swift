import Foundation
import SwiftData
import Testing
import StudyModels
import ExamEngine
import DomainInterfaces
@testable import Persistence

@MainActor struct SyncMergeTests {
    static let low = UUID(uuidString: "00000000-0000-0000-0000-000000000001")!
    static let high = UUID(uuidString: "00000000-0000-0000-0000-000000000002")!

    @Test(arguments: [0, 1, 2]) func cardStateKeepsLatestReviewOrSmallestID(scenario: Int) {
        let oldDate: Date? = scenario == 2 ? nil : PersistenceFixtures.now
        let newDate = scenario == 0 ? PersistenceFixtures.now.addingTimeInterval(1) : PersistenceFixtures.now
        let rows = [
            SyncMerge.Record(id: Self.low, kind: .cardState, examID: "alpha", target: ["C1"], date: oldDate),
            SyncMerge.Record(id: Self.high, kind: .cardState, examID: "alpha", target: ["C1"], date: newDate),
        ]
        let winner = scenario == 1 ? Self.low : Self.high
        let plan = SyncMerge.resolve(rows)
        #expect(plan.kept == [winner])
        #expect(plan.deleted == [winner == Self.low ? Self.high : Self.low])
        #expect(plan.abandoned.isEmpty && !plan.notifyUser)
        #expect(SyncMerge.resolve(rows.reversed()) == plan)
    }

    @Test(arguments: [SyncMerge.Kind.examPreference, .userSettings, .flag, .bookmark, .readMark])
    func dateRules(kind: SyncMerge.Kind) {
        let rows = [
            SyncMerge.Record(id: Self.low, kind: kind, examID: "alpha", target: ["item"], date: PersistenceFixtures.now),
            SyncMerge.Record(id: Self.high, kind: kind, examID: "alpha", target: ["item"], date: PersistenceFixtures.now.addingTimeInterval(1)),
        ]
        let newest = kind == .examPreference || kind == .userSettings
        #expect(SyncMerge.resolve(rows).kept == [newest ? Self.high : Self.low])
    }

    @Test func differentExamsAndAppendOnlyAreUntouched() {
        let rows = [
            SyncMerge.Record(id: Self.low, kind: .cardState, examID: "alpha", target: ["C1"]),
            SyncMerge.Record(id: Self.high, kind: .cardState, examID: "beta", target: ["C1"]),
        ]
        #expect(SyncMerge.resolve(rows).kept.count == 2)
        for kind in [SyncMerge.Kind.answerRecord, .reviewLog, .practiceServeLog] {
            let appendOnly = rows.map { SyncMerge.Record(id: $0.id, kind: kind, examID: "alpha", target: ["same"]) }
            #expect(SyncMerge.resolve(appendOnly).deleted.isEmpty)
            #expect(SyncMerge.resolve(appendOnly).kept.count == 2)
        }
        // 種別と対象IDを区切り文字で結合してキー衝突させない。
        let bookmarks = [
            SyncMerge.Record(id: Self.low, kind: .bookmark, examID: "alpha", target: ["question", "doc:1"]),
            SyncMerge.Record(id: Self.high, kind: .bookmark, examID: "alpha", target: ["doc", "question:1"]),
        ]
        #expect(SyncMerge.resolve(bookmarks).deleted.isEmpty)
    }

    @Test func attemptsKeepMostProgressAndIgnoreCompleted() {
        let completed = UUID()
        let rows = [
            SyncMerge.Record(id: Self.low, kind: .examAttempt, examID: "alpha", target: ["1"], progress: 12),
            SyncMerge.Record(id: Self.high, kind: .examAttempt, examID: "alpha", target: ["1"], progress: 30),
            SyncMerge.Record(id: completed, kind: .examAttempt, examID: "alpha", target: ["1"]),
        ]
        let plan = SyncMerge.resolve(rows)
        #expect(plan.kept.contains(Self.high) && plan.kept.contains(completed))
        #expect(plan.deleted.isEmpty && plan.abandoned == [Self.low] && plan.notifyUser)
    }

    @Test func deduplicatorKeepsAppendOnlyLogsAndIsIdempotent() async throws {
        let container = try PersistenceFixtures.container()
        let context = ModelContext(container)
        for offset in [0.0, 1.0] {
            let state = SchemaV1.CardState(); state.examID = "test-alpha"; state.cardID = "C1"
            state.lastReview = PersistenceFixtures.now.addingTimeInterval(offset)
            context.insert(state)
            let log = SchemaV1.ReviewLog(); log.examID = "test-alpha"; log.cardID = "C1"; log.rating = 3
            context.insert(log); log.cardState = state
            let answer = SchemaV1.AnswerRecord(); answer.examID = "test-alpha"; context.insert(answer)
            let serve = SchemaV1.PracticeServeLog(); serve.examID = "test-alpha"; context.insert(serve)
        }
        let other = SchemaV1.CardState(); other.examID = "test-beta"; other.cardID = "C1"; context.insert(other)
        try context.save()
        let deduplicator = SyncDeduplicator(modelContainer: container)
        let plan = try await deduplicator.run()
        #expect(plan.deleted.count == 1 && !plan.notifyUser)
        let read = ModelContext(container)
        let states = try read.fetch(FetchDescriptor<SchemaV1.CardState>())
        #expect(states.count == 2)
        #expect(states.first { $0.examID == "test-alpha" }?.lastReview == PersistenceFixtures.now.addingTimeInterval(1))
        #expect(try read.fetchCount(FetchDescriptor<SchemaV1.ReviewLog>()) == 2)
        #expect(try read.fetchCount(FetchDescriptor<SchemaV1.AnswerRecord>()) == 2)
        #expect(try read.fetchCount(FetchDescriptor<SchemaV1.PracticeServeLog>()) == 2)
        #expect(try await deduplicator.run().deleted.isEmpty == true)
    }

    @Test func deduplicatorAbandonsBothStatusAndSnapshot() async throws {
        let container = try PersistenceFixtures.container()
        let write = ModelContext(container)
        for index in [12, 30] {
            let row = SchemaV1.ExamAttempt(); row.examID = "test-alpha"; row.examSet = 1
            var snapshot = try PersistenceFixtures.snapshot()
            snapshot.order = QuestionOrder(items: (0..<40).map { .init(questionID: "Q\($0)", choiceIDs: ["a", "b"]) })
            snapshot.currentIndex = index
            row.sessionSnapshotJSON = try JSONEncoder().encode(snapshot); write.insert(row)
        }
        try write.save()
        let plan = try await SyncDeduplicator(modelContainer: container).run()
        #expect(plan.abandoned.count == 1 && plan.notifyUser)
        let rows = try ModelContext(container).fetch(FetchDescriptor<SchemaV1.ExamAttempt>())
        let abandoned = try #require(rows.first { $0.statusRaw == "abandoned" })
        #expect(try JSONDecoder().decode(ExamSession.Snapshot.self, from: abandoned.sessionSnapshotJSON).state == .abandoned)
        let active = try #require(rows.first { $0.statusRaw == "inProgress" })
        #expect(try JSONDecoder().decode(ExamSession.Snapshot.self, from: active.sessionSnapshotJSON).currentIndex == 30)
    }

    @Test func corruptedSnapshotPreventsAnyDeletion() async throws {
        let container = try PersistenceFixtures.container(), context: ModelContext
        context = ModelContext(container)
        for _ in 0..<2 { let flag = SchemaV1.Flag(); flag.examID = "alpha"; flag.questionID = "Q1"; context.insert(flag) }
        let invalid = SchemaV1.ExamAttempt(); invalid.examID = "alpha"; context.insert(invalid)
        try context.save()
        await #expect(throws: PersistenceError.self) { try await SyncDeduplicator(modelContainer: container).run() }
        #expect(try ModelContext(container).fetchCount(FetchDescriptor<SchemaV1.Flag>()) == 2)
    }
}
