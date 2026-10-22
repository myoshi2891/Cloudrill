import DomainModels
import Foundation
import StudyModels

public struct ExamTimerPolicy: Hashable, Sendable {
    /// 中断中にタイマーを止めるか。既定は止めない(本番と同じく時間は経過し続ける)
    public var pausesWhileSuspended: Bool
    /// 触覚フィードバックを出す残り時間
    public var warningThresholds: [Duration]

    public init(pausesWhileSuspended: Bool = false, warningThresholds: [Duration] = [.seconds(600), .seconds(300)]) {
        self.pausesWhileSuspended = pausesWhileSuspended
        self.warningThresholds = warningThresholds
    }
}

/// 模試のタイマー(BDD 6.2)。経過時間を数えず、期限の時刻を持つ(アプリが終了しても、再開時に正しい残り時間を出すため)。
public struct ExamTimer: Codable, Hashable, Sendable {
    public let duration: Duration
    public private(set) var deadline: Date
    /// 一時停止中の残り時間。動いている間は nil
    public private(set) var pausedRemaining: Duration?

    public init(startedAt: Date, duration: Duration) {
        self.duration = duration
        deadline = startedAt.adding(duration)
        pausedRemaining = nil
    }

    /// 試験時間は試験定義の `format.durationMinutes` から取る(Domain 層に試験の値を書かない)
    public init(startedAt: Date, definition: ExamDefinition) {
        self.init(startedAt: startedAt, duration: .seconds(definition.format.durationMinutes * 60))
    }

    public func remaining(at now: Date) -> Duration {
        if let pausedRemaining { return pausedRemaining }
        return max(.zero, deadline.duration(since: now))
    }

    public func isExpired(at now: Date) -> Bool {
        remaining(at: now) == .zero
    }

    public mutating func pause(at now: Date) {
        guard pausedRemaining == nil else { return }
        pausedRemaining = remaining(at: now)
    }

    public mutating func resume(at now: Date) {
        guard let pausedRemaining else { return }
        deadline = now.adding(pausedRemaining)
        self.pausedRemaining = nil
    }

    /// 前回の確認から今回までに越えた警告のしきい値(触覚フィードバックを1回だけ出すため)。
    /// しきい値ちょうどに達した場合も越えたとみなす。複数を越えたときは、短い方(より切迫した方)を返す。
    public func crossedThreshold(from previous: Date, to now: Date, policy: ExamTimerPolicy) -> Duration? {
        let before = remaining(at: previous)
        let after = remaining(at: now)
        return policy.warningThresholds.filter { before > $0 && after <= $0 }.min()
    }
}
