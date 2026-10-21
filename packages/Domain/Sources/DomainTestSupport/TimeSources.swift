import Foundation
import StudyModels
import Synchronization

/// 常に同じ時刻を返す
public struct FixedTimeSource: TimeSource {
    private let date: Date

    public init(_ date: Date) { self.date = date }

    public func now() -> Date { date }
}

/// `advance(by:)` で進める時刻。タイマーなど、時間の経過を確かめるテストで使う。
public final class ManualTimeSource: TimeSource {
    private let current: Mutex<Date>

    public init(_ start: Date) { current = Mutex(start) }

    public func now() -> Date { current.withLock { $0 } }

    public func advance(by duration: Duration) {
        current.withLock { $0 = $0.addingTimeInterval(duration.timeInterval) }
    }
}
