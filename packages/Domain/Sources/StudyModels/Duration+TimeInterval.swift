import Foundation

// Date の加減算(TimeInterval)と Duration の変換をここに集める

extension Duration {
    /// 秒の `Double`
    public var timeInterval: TimeInterval {
        let (seconds, attoseconds) = components
        return TimeInterval(seconds) + TimeInterval(attoseconds) / 1e18
    }
}

extension Date {
    public func adding(_ duration: Duration) -> Date {
        addingTimeInterval(duration.timeInterval)
    }

    /// `other` からこの時刻までの時間(この時刻の方が前なら負)
    public func duration(since other: Date) -> Duration {
        .seconds(timeIntervalSince(other))
    }
}
