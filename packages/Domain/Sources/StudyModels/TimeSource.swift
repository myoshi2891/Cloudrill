import Foundation

/// 現在時刻の取得元(DDD 2 章 C-09、6.1)。Domain 層では `Date()` を直接呼ばず、これを注入する。
/// 標準ライブラリの `Swift.Clock` と名前が衝突しないよう `TimeSource` にしている。
public protocol TimeSource: Sendable {
    func now() -> Date
}

/// 製品で使う実装
public struct SystemTimeSource: TimeSource {
    public init() {}
    public func now() -> Date { Date() }
}
