import Foundation

public enum SyncMerge {
    public enum Kind: String, Sendable, CaseIterable {
        case cardState, examPreference, userSettings, examAttempt, flag, bookmark, readMark
        case answerRecord, reviewLog, practiceServeLog
    }
    public struct Record: Sendable {
        public let id: UUID
        public let kind: Kind
        public let examID: String
        public let target: [String]
        public let date: Date?
        /// nil は提出・放棄済み。進行中だけを統合する。
        public let progress: Int?
        public init(id: UUID, kind: Kind, examID: String, target: [String] = [], date: Date? = nil, progress: Int? = nil) {
            self.id = id; self.kind = kind; self.examID = examID; self.target = target; self.date = date; self.progress = progress
        }
    }
    public struct Plan: Equatable, Sendable {
        public var kept: [UUID] = []
        public var deleted: [UUID] = []
        public var abandoned: [UUID] = []
        public var notifyUser: Bool { !abandoned.isEmpty }
        public init() {}
    }
    public static func resolve(_ records: [Record]) -> Plan { Plan() }
}
