import Foundation
import DomainModels
public enum DisplayLanguage: String, Sendable { case ja, en }
public enum SettingsError: Error, Equatable, Sendable { case outOfRange }
public struct UserSettings: Hashable, Sendable {
    public var currentExamID: ExamID?
    public var displayLanguage: DisplayLanguage
    public var notificationsEnabled: Bool
    public var shuffleChoices: Bool
    public init(currentExamID: ExamID? = nil, displayLanguage: DisplayLanguage = .ja, notificationsEnabled: Bool = false, shuffleChoices: Bool = false) {
        self.currentExamID = currentExamID; self.displayLanguage = displayLanguage
        self.notificationsEnabled = notificationsEnabled; self.shuffleChoices = shuffleChoices
    }
}
public struct ExamPreference: Hashable, Sendable {
    public var examDate: Date?
    public private(set) var dailyNewCards: Int = 20
    public private(set) var dailyReviewLimit: Int = 200
    public private(set) var desiredRetention: Double = 0.9
    public var autoCardFromMistakes: Bool = true
    public static let `default` = ExamPreference()
    public init() {}
    public init(desiredRetention: Double, examDate: Date? = nil, dailyNewCards: Int = 20, dailyReviewLimit: Int = 200, autoCardFromMistakes: Bool = true) throws(SettingsError) {
        self.desiredRetention = desiredRetention; self.examDate = examDate; self.dailyNewCards = dailyNewCards
        self.dailyReviewLimit = dailyReviewLimit; self.autoCardFromMistakes = autoCardFromMistakes
    }
}
