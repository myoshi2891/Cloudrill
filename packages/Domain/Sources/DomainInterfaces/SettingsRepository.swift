import Foundation
import DomainModels
import StudyModels
public protocol SettingsRepository: Sendable {
    func settings() async throws(PersistenceError) -> UserSettings
    func preference(examID: ExamID) async throws(PersistenceError) -> ExamPreference
    func save(settings: UserSettings, at date: Date) async throws(PersistenceError)
    func save(preference: ExamPreference, examID: ExamID, at date: Date) async throws(PersistenceError)
}
