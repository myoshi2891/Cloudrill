import Foundation
import Observation
import AppCore
import DomainInterfaces
import StudyModels

public enum ReportSubmitOutcome: Equatable, Sendable {
    /// 送信できた
    case sent
    /// 送信の仕組みがまだない(P5 まで)。キューに保存した
    case queued
    /// 送信できなかった(E-08)。キューに保存した
    case offline
}

/// 誤り報告のシート(SCR-090)。報告は先にキューへ保存し、送信できたらキューから外す。
@MainActor @Observable public final class ReportSheetViewModel {
    public static let commentLimit = 500
    public static let reasons = ReportReason.allCases

    public let context: QuestionReportContext
    public var reason: ReportReason?
    public var comment = ""
    public private(set) var isSubmitting = false
    public private(set) var outcome: ReportSubmitOutcome?
    public private(set) var error: String?

    private let queue: any ReportQueue
    private let sender: (any ReportSending)?
    private let metadata: ReportMetadata
    private let time: any TimeSource
    private let makeID: @Sendable () -> UUID

    public init(context: QuestionReportContext, queue: any ReportQueue, sender: (any ReportSending)?, metadata: ReportMetadata,
                time: any TimeSource, makeID: @escaping @Sendable () -> UUID = { UUID() }) {
        self.context = context; self.queue = queue; self.sender = sender
        self.metadata = metadata; self.time = time; self.makeID = makeID
    }

    /// 書記素(Character)単位。超過すると負の値になる。
    public var remainingCharacters: Int { Self.commentLimit - comment.count }
    public var isCommentTooLong: Bool { remainingCharacters < 0 }
    public var canSubmit: Bool { reason != nil && !isCommentTooLong && !isSubmitting && outcome == nil }
    public var privacyNotice: String { String(localized: "report.privacyNotice", bundle: .module) }
    public var message: String? {
        switch outcome {
        case .sent: String(localized: "report.sent", bundle: .module)
        case .queued: String(localized: "report.queued", bundle: .module)
        case .offline: String(localized: "report.offline", bundle: .module)
        case nil: nil
        }
    }

    public static func title(of reason: ReportReason) -> String {
        switch reason {
        case .wrongAnswer: String(localized: "report.reason.wrongAnswer", bundle: .module)
        case .unclearStem: String(localized: "report.reason.unclearStem", bundle: .module)
        case .typo: String(localized: "report.reason.typo", bundle: .module)
        case .outdated: String(localized: "report.reason.outdated", bundle: .module)
        case .brokenLink: String(localized: "report.reason.brokenLink", bundle: .module)
        case .other: String(localized: "report.reason.other", bundle: .module)
        }
    }

    public func submit() async {
        guard canSubmit, let reason else { return }
        isSubmitting = true
        error = nil
        defer { isSubmitting = false }
        let entry = PendingReportEntry(
            id: makeID(), examID: context.examID, questionID: context.questionID, questionRevision: context.questionRevision,
            packVersion: context.packVersion, reason: reason, comment: comment.trimmingCharacters(in: .whitespacesAndNewlines),
            appVersion: metadata.appVersion, locale: metadata.locale, createdAt: time.now())
        do {
            try await queue.enqueue(entry)
        } catch {
            self.error = String(localized: "report.saveFailed", bundle: .module)
            return
        }
        guard let sender else { outcome = .queued; return }
        guard await sender.send(entry) == .sent else { outcome = .offline; return }
        // 送信済みの削除に失敗しても、報告自体は届いている。キューに残った分は P5 の再送で重複しうるため、
        // 結果は送信済みとして扱う(握りつぶさず、次回の送信処理が扱う)。
        do { try await queue.remove(ids: [entry.id]) } catch { outcome = .sent; return }
        outcome = .sent
    }
}
