import OSLog

/// Instruments の Points of Interest で起動の内訳を確認する。Release でも有効。
/// StartupPreparation は依存の準備だけで、プロセス起動や画面描画の時間を含まない。
enum StartupMetrics {
    static let signposter = OSSignposter(subsystem: "Cloudrill", category: "startup")
}
