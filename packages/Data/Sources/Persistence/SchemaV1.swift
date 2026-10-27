import Foundation
import SwiftData
import StudyModels

/// 構造値の JSON と日時は、リポジトリが記録を作るときに実値へ置き換える。
/// UUID はここに集約せず、各レコードの初期化時に生成する。
private enum SchemaV1Defaults {
    static let emptyText = ""
    static let emptyJSON = Data()
    static let unsetDate = Date.distantPast
}

/// 学習履歴の初期スキーマ。CloudKit の同期に備え、unique 制約を付けず、
/// 列は既定値または Optional、リレーションは双方向の Optional とする。
public enum SchemaV1: VersionedSchema {
    public static var versionIdentifier: Schema.Version { Schema.Version(1, 0, 0) }

    public static var models: [any PersistentModel.Type] {
        [ExamAttempt.self, AnswerRecord.self, CardState.self, ReviewLog.self,
         PracticeServeLog.self, Flag.self, Bookmark.self, ReadMark.self,
         UserSettings.self, ExamPreference.self]
    }

    @Model public final class ExamAttempt {
        public var id: UUID = UUID()
        public var examID: String = SchemaV1Defaults.emptyText
        public var examSet: Int = 0
        public var packVersion: String = SchemaV1Defaults.emptyText
        public var startedAt: Date = SchemaV1Defaults.unsetDate
        public var statusRaw: String = "inProgress"
        public var submitReasonRaw: String? = nil
        public var submittedAt: Date? = nil
        public var correctCount: Int = 0
        public var totalCount: Int = 0
        public var sessionSnapshotJSON: Data = SchemaV1Defaults.emptyJSON
        @Relationship(deleteRule: .nullify, inverse: \AnswerRecord.attempt)
        public var answers: [AnswerRecord]? = nil
        public init() {}
    }

    @Model public final class AnswerRecord {
        public var id: UUID = UUID()
        public var examID: String = SchemaV1Defaults.emptyText
        public var questionID: String = SchemaV1Defaults.emptyText
        public var questionRevision: Int = 0
        public var domain: Int = 0
        public var subObjective: String = SchemaV1Defaults.emptyText
        public var caseStudy: String? = nil
        public var selectionJSON: Data = SchemaV1Defaults.emptyJSON
        public var isCorrect: Bool = false
        public var modeRaw: String = "practice"
        public var elapsedSeconds: Int = 0
        public var answeredAt: Date = SchemaV1Defaults.unsetDate
        public var attempt: ExamAttempt? = nil
        public init() {}
    }

    @Model public final class CardState {
        public var id: UUID = UUID()
        public var examID: String = SchemaV1Defaults.emptyText
        public var cardID: String = SchemaV1Defaults.emptyText
        public var fsrsCardJSON: Data = SchemaV1Defaults.emptyJSON
        public var due: Date = SchemaV1Defaults.unsetDate
        public var lastReview: Date? = nil
        // 同期後に重複した CardState を削除しても、追記のみの復習ログは残す。
        @Relationship(deleteRule: .nullify, inverse: \ReviewLog.cardState)
        public var reviewLogs: [ReviewLog]? = nil
        public init() {}
    }

    @Model public final class ReviewLog {
        public var id: UUID = UUID()
        public var examID: String = SchemaV1Defaults.emptyText
        public var cardID: String = SchemaV1Defaults.emptyText
        public var rating: Int = 0
        public var elapsedDays: Double = 0
        public var reviewedAt: Date = SchemaV1Defaults.unsetDate
        public var cardState: CardState? = nil
        public init() {}
    }

    @Model public final class PracticeServeLog {
        public var id: UUID = UUID()
        public var examID: String = SchemaV1Defaults.emptyText
        public var questionID: String = SchemaV1Defaults.emptyText
        public var servedAt: Date = SchemaV1Defaults.unsetDate
        public init() {}
    }

    @Model public final class Flag {
        public var id: UUID = UUID()
        public var examID: String = SchemaV1Defaults.emptyText
        public var questionID: String = SchemaV1Defaults.emptyText
        public var createdAt: Date = SchemaV1Defaults.unsetDate
        public init() {}
    }

    @Model public final class Bookmark {
        public var id: UUID = UUID()
        public var examID: String = SchemaV1Defaults.emptyText
        public var targetType: String = "question"
        public var targetID: String = SchemaV1Defaults.emptyText
        public var createdAt: Date = SchemaV1Defaults.unsetDate
        public init() {}
    }

    @Model public final class ReadMark {
        public var id: UUID = UUID()
        public var examID: String = SchemaV1Defaults.emptyText
        public var docSubObjective: String = SchemaV1Defaults.emptyText
        public var readAt: Date = SchemaV1Defaults.unsetDate
        public init() {}
    }

    @Model public final class UserSettings {
        public var id: UUID = UUID()
        public var currentExamID: String? = nil
        public var displayLanguage: String = "ja"
        public var notificationsEnabled: Bool = false
        public var shuffleChoices: Bool = false
        public var updatedAt: Date = SchemaV1Defaults.unsetDate
        public init() {}
    }

    @Model public final class ExamPreference {
        public var id: UUID = UUID()
        public var examID: String = SchemaV1Defaults.emptyText
        public var examDate: Date? = nil
        public var dailyNewCards: Int = StudyModels.ExamPreference.default.dailyNewCards
        public var dailyReviewLimit: Int = StudyModels.ExamPreference.default.dailyReviewLimit
        public var desiredRetention: Double = StudyModels.ExamPreference.default.desiredRetention
        public var autoCardFromMistakes: Bool = StudyModels.ExamPreference.default.autoCardFromMistakes
        public var updatedAt: Date = SchemaV1Defaults.unsetDate
        public init() {}
    }
}
