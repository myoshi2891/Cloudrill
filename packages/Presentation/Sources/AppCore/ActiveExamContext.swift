import Foundation
import Observation
import OSLog
import DomainModels
import DomainInterfaces
import StudyModels
import ExamEngine

public enum AppAlert: String, Sendable {
    case examUnavailable = "error.examUnavailable"
    case contentLoadFailed = "error.contentLoadFailed"
    case persistenceFailed = "error.persistenceFailed"
}

public struct ActiveExamState: Equatable, Sendable {
    public var examID: ExamID?
    public var preference: ExamPreference = .default
    public var needsSelection = true
    public var isLoading = false
    public var alert: AppAlert?
    public var fatal: AppAlert?
}

/// 起動時の選択規則。前回の試験が読めない場合は、別試験へ自動的に切り替えない。
public enum InitialExamSelection: Equatable, Sendable {
    case select(ExamID), choose, unavailable, fatal
    public static func resolve(available: Set<ExamID>, previous: ExamID?) -> Self {
        guard !available.isEmpty else { return .fatal }
        if let previous { return available.contains(previous) ? .select(previous) : .unavailable }
        if available.count == 1, let only = available.first { return .select(only) }
        return .choose
    }
}

@MainActor @Observable public final class ActiveExamContext {
    public private(set) var state = ActiveExamState()
    public let catalog: [CatalogEntry]
    public let router: AppRouter
    private let available: [ExamID: any ExamContentProvider]
    private let settings: any SettingsRepository
    private let attempts: any ExamAttemptRepository
    private let time: any TimeSource
    private var restored = false
    private let logger = Logger(subsystem: "Cloudrill", category: "content")

    public init(available: [ExamID: any ExamContentProvider], catalog: [CatalogEntry], failures: Set<ExamID>,
                settings: any SettingsRepository, attempts: any ExamAttemptRepository,
                time: any TimeSource, router: AppRouter) {
        let allowed = Set(catalog.filter { $0.status != .comingSoon }.map(\.id)).subtracting(failures)
        self.available = available.filter { allowed.contains($0.key) && $0.key == $0.value.definition.id }
        self.catalog = catalog; self.settings = settings; self.attempts = attempts; self.time = time; self.router = router
    }

    public var content: (any ExamContentProvider)? { state.examID.flatMap { available[$0] } }
    public func isAvailable(_ id: ExamID) -> Bool { available[id] != nil }

    public func restore() async {
        guard !restored, !state.isLoading else { return }
        state.isLoading = true
        defer { state.isLoading = false }
        state.alert = nil
        guard !available.isEmpty else { state.fatal = .contentLoadFailed; restored = true; return }
        do {
            let user = try await settings.settings()
            switch InitialExamSelection.resolve(available: Set(available.keys), previous: user.currentExamID) {
            case .select(let id): try await activate(id, user: user)
            case .choose: state.needsSelection = true
            case .unavailable: state.needsSelection = true; state.alert = .examUnavailable
            case .fatal: state.fatal = .contentLoadFailed
            }
            restored = true
        } catch { state.alert = .persistenceFailed; logger.error("試験選択の復元に失敗しました") }
    }

    public func switchExam(to id: ExamID) async {
        guard !state.isLoading, id != state.examID else { return }
        guard isAvailable(id) else { state.alert = .examUnavailable; return }
        // await 中の連打で、異なる試験の設定と画面が混在しないようにする。
        state.isLoading = true
        defer { state.isLoading = false }
        state.alert = nil
        do {
            let user = try await settings.settings()
            try await activate(id, user: user)
            restored = true
        } catch { state.alert = .persistenceFailed; logger.error("試験の切り替えに失敗しました") }
    }

    private func activate(_ id: ExamID, user: UserSettings) async throws {
        let preference = try await settings.preference(examID: id)
        var suspended: AttemptSnapshot?
        if let oldID = state.examID, let attempt = try await attempts.inProgress(examID: oldID),
           attempt.snapshot.state != .suspended {
            var session = ExamSession(snapshot: attempt.snapshot, timerPolicy: .init())
            try session.handle(.suspend, at: time.now())
            try await attempts.save(snapshot: session.snapshot, for: attempt.id)
            suspended = attempt
        }
        if user.currentExamID != id {
            var updated = user
            updated.currentExamID = id
            do {
                try await settings.save(settings: updated, at: time.now())
            } catch {
                // 切り替えを中止するため、旧試験の受験を中断前の状態に戻す。
                if let suspended { await revertSuspension(suspended) }
                throw error
            }
        }
        // 保存が成功するまでは、旧試験の画面と経路を保持する。
        state.examID = id; state.preference = preference; state.needsSelection = false; state.fatal = nil
        router.reset()
    }

    private func revertSuspension(_ attempt: AttemptSnapshot) async {
        do { try await attempts.save(snapshot: attempt.snapshot, for: attempt.id) }
        catch { logger.error("受験の中断の取り消しに失敗しました") }
    }
}
