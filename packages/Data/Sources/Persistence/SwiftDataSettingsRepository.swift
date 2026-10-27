import Foundation
import SwiftData
import DomainModels
import DomainInterfaces
import StudyModels
@ModelActor public actor SwiftDataSettingsRepository: SettingsRepository {
    public func settings() throws(PersistenceError) -> UserSettings { .init() }
    public func preference(examID: ExamID) throws(PersistenceError) -> ExamPreference { .default }
    public func save(settings: UserSettings, at date: Date) throws(PersistenceError) {}
    public func save(preference: ExamPreference, examID: ExamID, at date: Date) throws(PersistenceError) {}
}
