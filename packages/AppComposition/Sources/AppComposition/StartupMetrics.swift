import OSLog
#if canImport(UIKit)
import UIKit
#endif

/// Instruments の Points of Interest で起動の内訳を確認する。Release でも有効。
/// StartupPreparation は依存の準備だけで、プロセス起動や画面描画の時間を含まない。
enum StartupMetrics {
    static let signposter = OSSignposter(subsystem: "Cloudrill", category: .pointsOfInterest)

    @MainActor private static var didMarkReady = false

    /// 最初の操作可能な画面（試験選択、またはホームの読み込み完了）が描画された時点。プロセスごとに1回だけ記録する。
    /// 呼び出し側は操作可能な状態になってから呼ぶ。状態の変化を反映したフレームが確定するまで待ってから記録する。
    @MainActor static func markReadyAfterNextFrame() async {
        guard !didMarkReady else { return }
        await NextFrame.wait()
        // 待機中に画面が消えた（タスクが取り消された）場合は記録しない
        guard !Task.isCancelled, !didMarkReady else { return }
        didMarkReady = true
        signposter.emitEvent("StartupReady")
    }

    /// 起動時の選択復元が保存エラーで失敗した時点。StartupReady とは別に記録し、以降の StartupReady は記録しない
    /// （再選択などの操作時間が起動時間に混ざるため）。
    @MainActor static func markPersistenceFailure() {
        guard !didMarkReady else { return }
        didMarkReady = true
        signposter.emitEvent("StartupPersistenceFailed")
    }
}

/// 次の画面更新(vsync)まで待つ。その時点で、直前の実行ループで確定した View の更新は描画対象になっている。
@MainActor private final class NextFrame: NSObject {
    #if canImport(UIKit)
    private var continuation: CheckedContinuation<Void, Never>?
    private var link: CADisplayLink?

    static func wait() async {
        let frame = NextFrame()
        await withCheckedContinuation { continuation in
            frame.continuation = continuation
            let link = CADisplayLink(target: frame, selector: #selector(tick))
            frame.link = link
            link.add(to: .main, forMode: .common)
        }
    }

    @objc private func tick() {
        // CADisplayLink は target を保持するため、無効化して循環参照を解く
        link?.invalidate(); link = nil
        continuation?.resume(); continuation = nil
    }
    #else
    // macOS はアプリの対象外（パッケージのテストでビルドするだけ）。実行ループを1回譲る。
    static func wait() async { await Task.yield() }
    #endif
}
