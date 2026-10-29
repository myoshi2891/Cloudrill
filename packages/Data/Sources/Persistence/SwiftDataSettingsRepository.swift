import Foundation
import SwiftData
import DomainModels
import DomainInterfaces
import StudyModels
@ModelActor public actor SwiftDataSettingsRepository: SettingsRepository {
    private func latestSettings() throws -> SchemaV1.UserSettings? {
        // 全体設定だけは試験で絞らない。同日時なら UUID 順で決定論的に選ぶ。
        try modelContext.fetch(FetchDescriptor<SchemaV1.UserSettings>()).sorted {
            $0.updatedAt == $1.updatedAt ? $0.id.uuidString < $1.id.uuidString : $0.updatedAt > $1.updatedAt
        }.first
    }
    private func latestPreference(_ examID: ExamID) throws -> SchemaV1.ExamPreference? {
        let exam = examID.rawValue
        return try modelContext.fetch(FetchDescriptor<SchemaV1.ExamPreference>(predicate: #Predicate { $0.examID == exam })).sorted {
            $0.updatedAt == $1.updatedAt ? $0.id.uuidString < $1.id.uuidString : $0.updatedAt > $1.updatedAt
        }.first
    }
    public func settings() throws(PersistenceError) -> UserSettings {
        try Storage.read {
            guard let row = try latestSettings() else { return UserSettings() }
            guard let language = DisplayLanguage(rawValue: row.displayLanguage) else { throw PersistenceError.corrupted("unknown display language") }
            return UserSettings(currentExamID: row.currentExamID.map(ExamID.init(rawValue:)), displayLanguage: language,
                                notificationsEnabled: row.notificationsEnabled, shuffleChoices: row.shuffleChoices)
        }
    }
    public func preference(examID: ExamID) throws(PersistenceError) -> ExamPreference {
        try Storage.read {
            guard let row = try latestPreference(examID) else { return .default }
            return try ExamPreference(desiredRetention: row.desiredRetention, examDate: row.examDate,
                                      dailyNewCards: row.dailyNewCards, dailyReviewLimit: row.dailyReviewLimit,
                                      autoCardFromMistakes: row.autoCardFromMistakes)
        }
    }
    public func save(settings: UserSettings, at date: Date) throws(PersistenceError) {
        try Storage.write(modelContext, saver: ContextSaver()) {
            let row = try latestSettings() ?? SchemaV1.UserSettings()
            row.currentExamID = settings.currentExamID?.rawValue; row.displayLanguage = settings.displayLanguage.rawValue
            row.notificationsEnabled = settings.notificationsEnabled; row.shuffleChoices = settings.shuffleChoices
            row.updatedAt = date; modelContext.insert(row)
        }
    }
    public func save(preference: ExamPreference, examID: ExamID, at date: Date) throws(PersistenceError) {
        try Storage.write(modelContext, saver: ContextSaver()) {
            let row = try latestPreference(examID) ?? SchemaV1.ExamPreference()
            row.examID = examID.rawValue; row.examDate = preference.examDate
            row.dailyNewCards = preference.dailyNewCards; row.dailyReviewLimit = preference.dailyReviewLimit
            row.desiredRetention = preference.desiredRetention; row.autoCardFromMistakes = preference.autoCardFromMistakes
            row.updatedAt = date; modelContext.insert(row)
        }
    }
}
