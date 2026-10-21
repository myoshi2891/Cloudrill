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
/// P1-S05 では状態機械が使う部分だけを定義する。しきい値の判定と試験定義からの生成は P1-S06 で追加する。
public struct ExamTimer: Codable, Hashable, Sendable {
    public let duration: Duration
    public private(set) var deadline: Date
    /// 一時停止中の残り時間。動いている間は nil
    public private(set) var pausedRemaining: Duration?

    public init(startedAt: Date, duration: Duration) {
        self.duration = duration
        deadline = startedAt.addingTimeInterval(duration.timeInterval)
        pausedRemaining = nil
    }

    public func remaining(at now: Date) -> Duration {
        if let pausedRemaining { return pausedRemaining }
        return max(.zero, .seconds(deadline.timeIntervalSince(now)))
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
        deadline = now.addingTimeInterval(pausedRemaining.timeInterval)
        self.pausedRemaining = nil
    }
}
