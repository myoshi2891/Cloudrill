import Foundation

extension Duration {
    /// 秒の `Double`。`Date` の加減算(`TimeInterval`)と `Duration` の変換をここに集める。
    public var timeInterval: TimeInterval {
        let (seconds, attoseconds) = components
        return TimeInterval(seconds) + TimeInterval(attoseconds) / 1e18
    }
}
