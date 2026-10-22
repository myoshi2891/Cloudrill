/// 乱数の列が同じなら、Swift のバージョンによらず同じ結果になるシャッフル(DDD 6.3)。
/// 標準ライブラリの `shuffled(using:)` と `random(in:using:)` は、実装が版の間で同じとは限らないので使わない。
/// アルゴリズムを変えると、ゴールデンテスト(ExamOrderBuilderTests.shuffleGolden)が失敗する。
public enum DeterministicShuffle {
    /// Fisher–Yates(末尾から、0...i の位置と入れ替える)
    public static func shuffled<Element>(_ elements: [Element], using rng: inout some RandomNumberGenerator) -> [Element] {
        var result = elements
        guard result.count > 1 else { return result }
        for i in stride(from: result.count - 1, to: 0, by: -1) {
            let j = Int(boundedRandom(below: UInt64(i + 1), using: &rng))
            result.swapAt(i, j)
        }
        return result
    }

    /// 0..<bound の一様な乱数。Lemire の方法(乗算の上位 64 ビット)で、偏りを棄却で取り除く。
    static func boundedRandom(below bound: UInt64, using rng: inout some RandomNumberGenerator) -> UInt64 {
        precondition(bound > 0, "bound は 1 以上が必要")
        var (high, low) = bound.multipliedFullWidth(by: rng.next())
        if low < bound {
            let threshold = (0 &- bound) % bound
            while low < threshold {
                (high, low) = bound.multipliedFullWidth(by: rng.next())
            }
        }
        return high
    }
}
