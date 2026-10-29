import Foundation
import SwiftData
import Testing
import DomainInterfaces
import StudyModels
@testable import Persistence
@MainActor struct SettingsRepositoryTests {
    @Test func defaultsWhenEmptyAndSavesCurrentExam() async throws {
        let repo = SwiftDataSettingsRepository(modelContainer: try PersistenceFixtures.container())
        var settings = try await repo.settings()
        #expect(settings.displayLanguage == .ja && !settings.shuffleChoices && settings.currentExamID == nil)
        let preference = try await repo.preference(examID: "test-alpha")
        #expect(preference.dailyNewCards == 20 && preference.dailyReviewLimit == 200)
        #expect(preference.desiredRetention == 0.9 && preference.autoCardFromMistakes && preference.examDate == nil)
        settings.currentExamID = "test-beta"; settings.shuffleChoices = true
        try await repo.save(settings: settings, at: PersistenceFixtures.now)
        #expect(try await repo.settings() == settings)
    }
    @Test func preferenceIsPerExam() async throws {
        let repo = SwiftDataSettingsRepository(modelContainer: try PersistenceFixtures.container())
        var preference = ExamPreference.default; preference.examDate = PersistenceFixtures.now
        try await repo.save(preference: preference, examID: "test-alpha", at: PersistenceFixtures.now)
        #expect(try await repo.preference(examID: "test-alpha").examDate == PersistenceFixtures.now)
        #expect(try await repo.preference(examID: "test-beta").examDate == nil)
    }
    @Test(arguments: [0.99, 0.79, Double.nan]) func retentionValidated(retention: Double) {
        #expect(throws: SettingsError.outOfRange) { try ExamPreference(desiredRetention: retention) }
    }
    @Test func duplicateRowsUseLatestAndUnknownLanguageFails() async throws {
        let container = try PersistenceFixtures.container()
        // 同じコンテナに、同期で生じうる重複を再現する。
        let storeContext = ModelContext(container)
        for offset in [0.0, 1.0] {
            let row = SchemaV1.ExamPreference(); row.examID = "test-alpha"
            row.updatedAt = PersistenceFixtures.now.addingTimeInterval(offset); row.dailyNewCards = Int(offset) + 30
            storeContext.insert(row)
        }
        try storeContext.save()
        let repo = SwiftDataSettingsRepository(modelContainer: container)
        #expect(try await repo.preference(examID: "test-alpha").dailyNewCards == 31)
        let bad = SchemaV1.UserSettings(); bad.displayLanguage = "future"
        storeContext.insert(bad); try storeContext.save()
        await #expect(throws: PersistenceError.corrupted("unknown display language")) { try await repo.settings() }
    }
}
