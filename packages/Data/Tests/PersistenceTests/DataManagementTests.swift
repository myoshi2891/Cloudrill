import Foundation
import SwiftData
import Testing
import DomainInterfaces
@testable import Persistence

@MainActor enum DataManagementFixtures {
    static let payload = Data([0, 1, 2, 255])
    static func seed(_ context: ModelContext, exam: String) throws {
        let now = PersistenceFixtures.now
        let attempt = SchemaV1.ExamAttempt(); attempt.examID = exam; attempt.examSet = 2; attempt.packVersion = "1.2.0"
        attempt.startedAt = now; attempt.statusRaw = "submitted"; attempt.submitReasonRaw = "user"
        attempt.submittedAt = now.addingTimeInterval(60); attempt.correctCount = 1; attempt.totalCount = 2
        attempt.sessionSnapshotJSON = payload; context.insert(attempt)
        let answer = SchemaV1.AnswerRecord(); answer.examID = exam; answer.questionID = "Q1"; answer.questionRevision = 3
        answer.domain = 2; answer.subObjective = "2.1"; answer.selectionJSON = payload; answer.isCorrect = true
        answer.modeRaw = "exam"; answer.elapsedSeconds = 7; answer.answeredAt = now; context.insert(answer); answer.attempt = attempt
        let state = SchemaV1.CardState(); state.examID = exam; state.cardID = "C1"; state.fsrsCardJSON = payload
        state.due = now.addingTimeInterval(10); state.lastReview = now; context.insert(state)
        let log = SchemaV1.ReviewLog(); log.examID = exam; log.cardID = "C1"; log.rating = 3; log.elapsedDays = 2.5
        log.reviewedAt = now; context.insert(log); log.cardState = state
        let serve = SchemaV1.PracticeServeLog(); serve.examID = exam; serve.questionID = "Q1"; serve.servedAt = now; context.insert(serve)
        let flag = SchemaV1.Flag(); flag.examID = exam; flag.questionID = "Q1"; flag.createdAt = now; context.insert(flag)
        let bookmark = SchemaV1.Bookmark(); bookmark.examID = exam; bookmark.targetType = "doc"; bookmark.targetID = "3.2"
        bookmark.createdAt = now; context.insert(bookmark)
        let read = SchemaV1.ReadMark(); read.examID = exam; read.docSubObjective = "3.2"; read.readAt = now; context.insert(read)
        let preference = SchemaV1.ExamPreference(); preference.examID = exam; preference.examDate = now.addingTimeInterval(86400)
        preference.dailyNewCards = 10; preference.dailyReviewLimit = 50; preference.desiredRetention = 0.85
        preference.autoCardFromMistakes = false; preference.updatedAt = now; context.insert(preference)
        if exam == "test-alpha" {
            let settings = SchemaV1.UserSettings(); settings.currentExamID = "test-beta"; settings.displayLanguage = "en"
            settings.notificationsEnabled = true; settings.shuffleChoices = true; settings.updatedAt = now; context.insert(settings)
        }
        try context.save()
    }
    static func entities(_ data: Data) throws -> [String: [[String: Any]]] {
        let document = try #require(JSONSerialization.jsonObject(with: data) as? [String: Any])
        return try #require(document["entities"] as? [String: [[String: Any]]])
    }
}

@MainActor struct DataManagementTests {
    @Test func exportContainsEveryEntityColumnAndRelationship() async throws {
        let container = try PersistenceFixtures.container()
        try DataManagementFixtures.seed(ModelContext(container), exam: "test-alpha")
        let data = try await DataManagement(modelContainer: container).export(examID: nil)
        let document = try #require(JSONSerialization.jsonObject(with: data) as? [String: Any])
        #expect(document["exportVersion"] as? Int == 1 && document["schema"] as? String == "V1")
        let entities = try DataManagementFixtures.entities(data)
        #expect(entities.count == 10)
        for entity in Schema(SchemaV1.models).entities {
            let rows = try #require(entities[entity.name]); #expect(rows.count == 1)
            let row = try #require(rows.first)
            #expect(Set(row.keys) == Set(entity.properties.map(\.name)), "\(entity.name) の全列とリレーション")
        }
        let attempt = try #require(entities["ExamAttempt"]?.first), answer = try #require(entities["AnswerRecord"]?.first)
        #expect(attempt["sessionSnapshotJSON"] as? String == DataManagementFixtures.payload.base64EncodedString())
        #expect(attempt["answers"] as? [String] == [try #require(answer["id"] as? String)])
        #expect(answer["attempt"] as? String == attempt["id"] as? String)
        #expect(answer["selectionJSON"] as? String == DataManagementFixtures.payload.base64EncodedString())
        #expect(answer["caseStudy"] is NSNull)
        #expect(answer["questionRevision"] as? Int == 3 && answer["elapsedSeconds"] as? Int == 7)
        #expect(attempt["startedAt"] as? Double == PersistenceFixtures.now.timeIntervalSince1970)
        let state = try #require(entities["CardState"]?.first), log = try #require(entities["ReviewLog"]?.first)
        #expect(state["fsrsCardJSON"] as? String == DataManagementFixtures.payload.base64EncodedString())
        #expect(state["reviewLogs"] as? [String] == [try #require(log["id"] as? String)])
        #expect(log["cardState"] as? String == state["id"] as? String)
        #expect(log["elapsedDays"] as? Double == 2.5)
        #expect(entities["UserSettings"]?.first?["notificationsEnabled"] as? Bool == true)
        #expect(entities["ExamPreference"]?.first?["desiredRetention"] as? Double == 0.85)
    }

    @Test func exportIsDeterministicAndCanFilterByExam() async throws {
        let container = try PersistenceFixtures.container(), context: ModelContext
        context = ModelContext(container)
        try DataManagementFixtures.seed(context, exam: "test-beta"); try DataManagementFixtures.seed(context, exam: "test-alpha")
        let repo = DataManagement(modelContainer: container)
        let first = try await repo.export(examID: nil), second = try await repo.export(examID: nil)
        #expect(first == second)
        for records in try DataManagementFixtures.entities(first).values {
            let ids = records.compactMap { $0["id"] as? String }; #expect(ids == ids.sorted())
        }
        let filtered = try DataManagementFixtures.entities(await repo.export(examID: "test-alpha"))
        #expect(filtered["UserSettings"]?.isEmpty == true)
        for (name, records) in filtered where name != "UserSettings" {
            #expect(records.count == 1)
            #expect(records.allSatisfy { $0["examID"] as? String == "test-alpha" })
        }
    }

    @Test func deleteExamPreservesOtherExamAndGlobalSettingsThenDeleteAll() async throws {
        let container = try PersistenceFixtures.container(), context: ModelContext
        context = ModelContext(container)
        try DataManagementFixtures.seed(context, exam: "test-alpha"); try DataManagementFixtures.seed(context, exam: "test-beta")
        let repo = DataManagement(modelContainer: container)
        let before = try await repo.export(examID: "test-beta")
        try await repo.deleteAll(examID: "test-alpha")
        #expect(try await repo.export(examID: "test-beta") == before)
        let remaining = try DataManagementFixtures.entities(await repo.export(examID: nil))
        #expect(remaining.count == 10)
        for records in remaining.values { #expect(records.count == 1) }
        #expect(try DataManagementFixtures.entities(await repo.export(examID: "test-alpha")).values.allSatisfy { $0.isEmpty })
        try await repo.deleteAll(examID: nil)
        #expect(try DataManagementFixtures.entities(await repo.export(examID: nil)).values.allSatisfy { $0.isEmpty })
    }

    @Test func failedDeletionRollsBack() async throws {
        let container = try PersistenceFixtures.container()
        try DataManagementFixtures.seed(ModelContext(container), exam: "test-alpha")
        let saver = FailingSaver(failures: 2)
        let repo = DataManagement(modelContainer: container, saver: saver)
        let before = try await repo.export(examID: nil)
        await #expect(throws: PersistenceError.self) { try await repo.deleteAll(examID: nil) }
        #expect(saver.count == 2)
        #expect(try await repo.export(examID: nil) == before)
        #expect(try await DataManagement(modelContainer: container).export(examID: nil) == before)
    }
}
