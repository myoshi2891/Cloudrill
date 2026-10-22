import Foundation

/// 日数の計算をここに集める(タイムゾーンによらず、86400 秒を 1 日とする。リファレンス実装と同じ)
enum ElapsedDays {
    static let secondsPerDay: Double = 86_400

    static func fractional(from start: Date, to end: Date) -> Double {
        end.timeIntervalSince(start) / secondsPerDay
    }

    /// 切り捨ての整数日(py-fsrs の `timedelta.days` と同じく、負の値は -∞ 方向に丸める)
    static func whole(from start: Date, to end: Date) -> Int {
        Int(fractional(from: start, to: end).rounded(.down))
    }
}
