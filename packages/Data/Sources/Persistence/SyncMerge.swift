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
    private struct Key: Hashable {
        var kind: Kind
        var examID: String
        var target: [String]
    }
    private enum Rule { case latest, earliest, progress }
    // 追記のみの種類は表に含めず、そのまま残す。
    private static let rules: [Kind: Rule] = [
        .cardState: .latest, .examPreference: .latest, .userSettings: .latest,
        .examAttempt: .progress, .flag: .earliest, .bookmark: .earliest, .readMark: .earliest,
    ]
    public static func resolve(_ records: [Record]) -> Plan {
        var plan = Plan()
        var groups: [Key: [Record]] = [:]
        for row in records {
            guard rules[row.kind] != nil, row.kind != .examAttempt || row.progress != nil else {
                plan.kept.append(row.id); continue
            }
            let global = row.kind == .userSettings
            let noTarget = global || row.kind == .examPreference
            let key = Key(kind: row.kind, examID: global ? "" : row.examID, target: noTarget ? [] : row.target)
            groups[key, default: []].append(row)
        }
        for (key, rows) in groups {
            let ordered = rows.sorted { left, right in
                switch rules[key.kind] {
                case .progress:
                    if left.progress != right.progress { return (left.progress ?? 0) > (right.progress ?? 0) }
                case .latest, .earliest:
                    // nil の lastReview は実際のどの日時よりも古い。
                    if left.date != right.date {
                        if left.date == nil { return rules[key.kind] == .earliest }
                        if right.date == nil { return rules[key.kind] == .latest }
                        if let a = left.date, let b = right.date { return rules[key.kind] == .latest ? a > b : a < b }
                    }
                case nil: break
                }
                return left.id.uuidString < right.id.uuidString
            }
            if let first = ordered.first { plan.kept.append(first.id) }
            let others = ordered.dropFirst().map(\.id)
            if key.kind == .examAttempt { plan.abandoned += others } else { plan.deleted += others }
        }
        plan.kept.sort { $0.uuidString < $1.uuidString }
        plan.deleted.sort { $0.uuidString < $1.uuidString }
        plan.abandoned.sort { $0.uuidString < $1.uuidString }
        return plan
    }
}
