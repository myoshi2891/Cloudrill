import OSLog

/// Instruments の Points of Interest で起動の内訳を確認する。Release でも有効。
/// StartupPreparation は依存の準備だけで、プロセス起動や画面描画の時間を含まない。
enum StartupMetrics {
    static let signposter = OSSignposter(subsystem: "Cloudrill", category: .pointsOfInterest)

    @MainActor private static var didMarkReady = false

    /// 起動後に最初の操作可能な画面（試験選択、またはホームの読み込み完了）が表示された時点。プロセスごとに1回だけ記録する。
    @MainActor static func markReady() {
        guard !didMarkReady else { return }
        didMarkReady = true
        signposter.emitEvent("StartupReady")
    }
}
