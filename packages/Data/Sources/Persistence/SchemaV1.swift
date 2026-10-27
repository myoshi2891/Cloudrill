import Foundation
import SwiftData

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
        public var examID: String = ""
        public var examSet: Int = 0
        public var packVersion: String = ""
        public var startedAt: Date = Date.distantPast
        public var statusRaw: String = "inProgress"
        public var submitReasonRaw: String? = nil
        public var submittedAt: Date? = nil
        public var correctCount: Int = 0
        public var totalCount: Int = 0
        public var sessionSnapshotJSON: Data = Data()
        @Relationship(deleteRule: .nullify, inverse: \AnswerRecord.attempt)
        public var answers: [AnswerRecord]? = nil
        public init() {}
    }

    @Model public final class AnswerRecord {
        public var id: UUID = UUID()
        public var examID: String = ""
        public var questionID: String = ""
        public var questionRevision: Int = 0
        public var domain: Int = 0
        public var subObjective: String = ""
        public var caseStudy: String? = nil
        public var selectionJSON: Data = Data()
        public var isCorrect: Bool = false
        public var modeRaw: String = "practice"
        public var elapsedSeconds: Int = 0
        public var answeredAt: Date = Date.distantPast
        public var attempt: ExamAttempt? = nil
        public init() {}
    }

    @Model public final class CardState {
        public var id: UUID = UUID()
        public var examID: String = ""
        public var cardID: String = ""
        public var fsrsCardJSON: Data = Data()
        public var due: Date = Date.distantPast
        public var lastReview: Date? = nil
        // 同期後に重複した CardState を削除しても、追記のみの復習ログは残す。
        @Relationship(deleteRule: .nullify, inverse: \ReviewLog.cardState)
        public var reviewLogs: [ReviewLog]? = nil
        public init() {}
    }

    @Model public final class ReviewLog {
        public var id: UUID = UUID()
        public var examID: String = ""
        public var cardID: String = ""
        public var rating: Int = 0
        public var elapsedDays: Double = 0
        public var reviewedAt: Date = Date.distantPast
        public var cardState: CardState? = nil
        public init() {}
    }

    @Model public final class PracticeServeLog {
        public var id: UUID = UUID()
        public var examID: String = ""
        public var questionID: String = ""
        public var servedAt: Date = Date.distantPast
        public init() {}
    }

    @Model public final class Flag {
        public var id: UUID = UUID()
        public var examID: String = ""
        public var questionID: String = ""
        public var createdAt: Date = Date.distantPast
        public init() {}
    }

    @Model public final class Bookmark {
        public var id: UUID = UUID()
        public var examID: String = ""
        public var targetType: String = "question"
        public var targetID: String = ""
        public var createdAt: Date = Date.distantPast
        public init() {}
    }

    @Model public final class ReadMark {
        public var id: UUID = UUID()
        public var examID: String = ""
        public var docSubObjective: String = ""
        public var readAt: Date = Date.distantPast
        public init() {}
    }

    @Model public final class UserSettings {
        public var id: UUID = UUID()
        public var currentExamID: String? = nil
        public var displayLanguage: String = "ja"
        public var notificationsEnabled: Bool = false
        public var shuffleChoices: Bool = false
        public var updatedAt: Date = Date.distantPast
        public init() {}
    }

    @Model public final class ExamPreference {
        public var id: UUID = UUID()
        public var examID: String = ""
        public var examDate: Date? = nil
        public var dailyNewCards: Int = 20
        public var dailyReviewLimit: Int = 200
        public var desiredRetention: Double = 0.90
        public var autoCardFromMistakes: Bool = true
        public var updatedAt: Date = Date.distantPast
        public init() {}
    }
}
