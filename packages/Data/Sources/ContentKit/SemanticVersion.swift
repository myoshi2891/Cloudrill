import Foundation

/// SemVer 2.0.0 の優先順位。build metadata は等価性・ハッシュ・順序に含めない。
public struct SemanticVersion: Sendable, Hashable, Comparable, CustomStringConvertible {
    public let description: String
    private let core: [String]
    private let prerelease: [String]

    public init?(_ value: String) {
        let pattern = #"\A(0|[1-9][0-9]*)\.(0|[1-9][0-9]*)\.(0|[1-9][0-9]*)(-[0-9A-Za-z-]+(\.[0-9A-Za-z-]+)*)?(\+[0-9A-Za-z-]+(\.[0-9A-Za-z-]+)*)?\z"#
        guard value.range(of: pattern, options: .regularExpression) != nil else { return nil }
        let version = value.split(separator: "+", maxSplits: 1)[0]
        let parts = version.split(separator: "-", maxSplits: 1)
        let pre = parts.count == 2 ? parts[1].split(separator: ".").map(String.init) : []
        guard !pre.contains(where: { Self.numeric($0) && $0.count > 1 && $0.first == "0" }) else { return nil }
        description = value
        core = parts[0].split(separator: ".").map(String.init)
        prerelease = pre
    }
    public static func == (lhs: Self, rhs: Self) -> Bool { lhs.core == rhs.core && lhs.prerelease == rhs.prerelease }
    public func hash(into hasher: inout Hasher) { hasher.combine(core); hasher.combine(prerelease) }
    private static func numeric(_ value: String) -> Bool { value.utf8.allSatisfy { (48...57).contains($0) } }
    /// 任意の桁数を扱い、Int のオーバーフローで有効な版を拒否しない。
    private static func numericLess(_ a: String, _ b: String) -> Bool { a.count == b.count ? a < b : a.count < b.count }
    public static func < (lhs: Self, rhs: Self) -> Bool {
        for (a, b) in zip(lhs.core, rhs.core) where a != b { return numericLess(a, b) }
        if lhs.prerelease.isEmpty { return false }
        if rhs.prerelease.isEmpty { return true }
        for (a, b) in zip(lhs.prerelease, rhs.prerelease) where a != b {
            let an = numeric(a), bn = numeric(b)
            if an != bn { return an }
            return an ? numericLess(a, b) : a < b
        }
        return lhs.prerelease.count < rhs.prerelease.count
    }
}
