import Foundation
import DomainModels

/// 誤り報告の理由。順序と生の値は report-api(BDD 7.2)の `reason` と一致させる。
public enum ReportReason: String, CaseIterable, Codable, Sendable {
    case wrongAnswer, unclearStem, typo, outdated, brokenLink, other
}

/// 端末内の送信キューに置く報告。送信に必要な文脈(C-11)をすべて持つ。
/// 個人を識別する項目は持たない。`comment` は利用者の自由記述(500文字以内)。
public struct PendingReportEntry: Hashable, Sendable {
    public var id: UUID
    public var examID: ExamID
    public var questionID: String
    public var questionRevision: Int
    public var packVersion: String
    public var reason: ReportReason
    public var comment: String
    public var appVersion: String
    public var locale: String
    public var createdAt: Date
    public init(id: UUID, examID: ExamID, questionID: String, questionRevision: Int, packVersion: String,
                reason: ReportReason, comment: String, appVersion: String, locale: String, createdAt: Date) {
        self.id = id; self.examID = examID; self.questionID = questionID; self.questionRevision = questionRevision
        self.packVersion = packVersion; self.reason = reason; self.comment = comment
        self.appVersion = appVersion; self.locale = locale; self.createdAt = createdAt
    }
}

/// 送信前の報告を端末内に保存するキュー。学習履歴とは別に、端末間で同期しない。
public protocol ReportQueue: Sendable {
    func enqueue(_ entry: PendingReportEntry) async throws(PersistenceError)
    /// 古い順。`examID` が nil なら全試験。
    func pending(examID: ExamID?) async throws(PersistenceError) -> [PendingReportEntry]
    func remove(ids: Set<UUID>) async throws(PersistenceError)
    /// 全データ削除用。`examID` が nil なら全試験。
    func removeAll(examID: ExamID?) async throws(PersistenceError)
}

public enum ReportSendOutcome: Equatable, Sendable { case sent, offline }

/// 報告の送信。実装は P5 の `ReportClient`。送信できない場合はキューに残す。
public protocol ReportSending: Sendable {
    func send(_ entry: PendingReportEntry) async -> ReportSendOutcome
}
