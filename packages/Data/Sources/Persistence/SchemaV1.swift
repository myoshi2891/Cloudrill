import Foundation
import SwiftData

/// P3-S01 の assertion Red を確認するための仮実装。
/// 各モデルの列とリレーションは、先行テストに従って Green で追加する。
public enum SchemaV1: VersionedSchema {
    public static var versionIdentifier: Schema.Version { Schema.Version(1, 0, 0) }

    public static var models: [any PersistentModel.Type] {
        [ExamAttempt.self, AnswerRecord.self, CardState.self, ReviewLog.self,
         PracticeServeLog.self, Flag.self, Bookmark.self, ReadMark.self,
         UserSettings.self, ExamPreference.self]
    }

    @Model public final class ExamAttempt {
        public var id: UUID = UUID()
        public init() {}
    }

    @Model public final class AnswerRecord {
        public var id: UUID = UUID()
        public init() {}
    }

    @Model public final class CardState {
        public var id: UUID = UUID()
        public init() {}
    }

    @Model public final class ReviewLog {
        public var id: UUID = UUID()
        public init() {}
    }

    @Model public final class PracticeServeLog {
        public var id: UUID = UUID()
        public init() {}
    }

    @Model public final class Flag {
        public var id: UUID = UUID()
        public var examID: String = ""
        public var questionID: String = ""
        public init() {}
    }

    @Model public final class Bookmark {
        public var id: UUID = UUID()
        public init() {}
    }

    @Model public final class ReadMark {
        public var id: UUID = UUID()
        public init() {}
    }

    @Model public final class UserSettings {
        public var id: UUID = UUID()
        public init() {}
    }

    @Model public final class ExamPreference {
        public var id: UUID = UUID()
        public init() {}
    }
}
