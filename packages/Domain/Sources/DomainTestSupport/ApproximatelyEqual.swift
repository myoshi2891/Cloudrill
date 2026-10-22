/// 浮動小数点の比較(比重の合計や準備度など、丸め誤差が出る値に使う)
public func approximatelyEqual(_ lhs: Double, _ rhs: Double, tolerance: Double = 1e-9) -> Bool {
    abs(lhs - rhs) <= tolerance
}
