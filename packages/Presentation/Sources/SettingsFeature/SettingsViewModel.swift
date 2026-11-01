import Foundation
import Observation
import DomainModels
import DomainInterfaces
import StudyModels

public enum DataDeletionScope: Equatable, Sendable {
    /// 選択中の試験の学習データだけ
    case exam
    /// 全試験の学習データと設定
    case all
}

/// 設定(SCR-002)。試験ごとの学習設定、問題の表示、データの書き出し・削除、アプリについて。
@MainActor @Observable public final class SettingsViewModel {
    public static let newCardsRange = 0...100
    public static let newCardsStep = 5
    public static let reviewLimitRange = 0...1000
    public static let reviewLimitStep = 10

    public let examID: ExamID
    public let examName: String
    public let vendors: [Vendor]
    public let appVersion: String
    public private(set) var preference: ExamPreference = .default
    public private(set) var shuffleChoices = false
    public private(set) var isLoaded = false
    public private(set) var exportFile: URL?
    public private(set) var isExporting = false
    public private(set) var pendingDeletion: DataDeletionScope?
    public private(set) var isDeleting = false
    public private(set) var error: String?

    private let settings: any SettingsRepository
    private let dataManagement: any DataManagementRepository
    private let reports: any ReportQueue
    private let time: any TimeSource
    private let exportDirectory: URL
    private let timeZone: TimeZone
    private let onDeleted: @MainActor (ExamID?) async -> Void
    private var savedPreference: ExamPreference = .default

    public init(examID: ExamID, examName: String, vendors: [Vendor], appVersion: String,
                settings: any SettingsRepository, dataManagement: any DataManagementRepository, reports: any ReportQueue,
                time: any TimeSource, exportDirectory: URL = FileManager.default.temporaryDirectory, timeZone: TimeZone = .current,
                onDeleted: @escaping @MainActor (ExamID?) async -> Void) {
        self.examID = examID; self.examName = examName; self.vendors = vendors; self.appVersion = appVersion
        self.settings = settings; self.dataManagement = dataManagement; self.reports = reports; self.time = time
        self.exportDirectory = exportDirectory; self.timeZone = timeZone; self.onDeleted = onDeleted
    }

    public var unofficialNotice: String { String(localized: "settings.about.unofficial", bundle: .module) }
    public var noGuaranteeNotice: String { String(localized: "settings.about.noGuarantee", bundle: .module) }
    public var isBusy: Bool { isDeleting || isExporting }

    public func load() async {
        do {
            let user = try await settings.settings()
            let loaded = try await settings.preference(examID: examID)
            shuffleChoices = user.shuffleChoices
            preference = loaded; savedPreference = loaded
            isLoaded = true; error = nil
        } catch {
            self.error = String(localized: "settings.loadFailed", bundle: .module)
        }
    }

    // MARK: 試験ごとの学習設定(FR-CARD-05)

    public func setDailyNewCards(_ value: Int) async {
        await savePreference(dailyNewCards: value, dailyReviewLimit: preference.dailyReviewLimit,
                             autoCard: preference.autoCardFromMistakes)
    }
    public func setDailyReviewLimit(_ value: Int) async {
        await savePreference(dailyNewCards: preference.dailyNewCards, dailyReviewLimit: value,
                             autoCard: preference.autoCardFromMistakes)
    }
    public func setAutoCardFromMistakes(_ value: Bool) async {
        await savePreference(dailyNewCards: preference.dailyNewCards, dailyReviewLimit: preference.dailyReviewLimit, autoCard: value)
    }

    private func savePreference(dailyNewCards: Int, dailyReviewLimit: Int, autoCard: Bool) async {
        guard isLoaded else { return }
        let updated: ExamPreference
        do {
            updated = try ExamPreference(desiredRetention: preference.desiredRetention, examDate: preference.examDate,
                                         dailyNewCards: dailyNewCards, dailyReviewLimit: dailyReviewLimit,
                                         autoCardFromMistakes: autoCard)
        } catch {
            self.error = String(localized: "settings.saveFailed", bundle: .module)
            return
        }
        preference = updated
        do {
            try await settings.save(preference: updated, examID: examID, at: time.now())
            savedPreference = updated; error = nil
        } catch {
            preference = savedPreference
            self.error = String(localized: "settings.saveFailed", bundle: .module)
        }
    }

    // MARK: 問題の表示(FR-EXAM-12)

    /// 以後に開始する模試に反映する。進行中の模試の出題順は受験記録に固定されているので変わらない。
    public func setShuffleChoices(_ value: Bool) async {
        guard isLoaded else { return }
        let previous = shuffleChoices
        shuffleChoices = value
        do {
            // 試験の選択など他の項目を上書きしないよう、保存直前の値を読み直す
            var user = try await settings.settings()
            user.shuffleChoices = value
            try await settings.save(settings: user, at: time.now())
            error = nil
        } catch {
            shuffleChoices = previous
            self.error = String(localized: "settings.saveFailed", bundle: .module)
        }
    }

    // MARK: データ(FR-ACCT-03)

    /// 全試験の学習データを JSON ファイルに書き出す。View は共有シートに渡す。
    public func exportData() async {
        guard !isBusy else { return }
        isExporting = true
        defer { isExporting = false }
        exportFile = nil
        do {
            let data = try await dataManagement.export(examID: nil)
            let url = exportDirectory.appending(path: exportFileName())
            try data.write(to: url, options: .atomic)
            exportFile = url; error = nil
        } catch {
            self.error = String(localized: "settings.exportFailed", bundle: .module)
        }
    }

    private func exportFileName() -> String {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = timeZone
        let parts = calendar.dateComponents([.year, .month, .day], from: time.now())
        return String(format: "cloudrill-export-%04d%02d%02d.json", parts.year ?? 0, parts.month ?? 0, parts.day ?? 0)
    }

    public func requestDelete(_ scope: DataDeletionScope) {
        guard !isBusy else { return }
        pendingDeletion = scope
    }
    public func cancelDelete() { pendingDeletion = nil }

    /// 確認ダイアログで確定したときだけ呼ぶ。誤り報告のキューも同じ範囲を削除する。
    /// ダイアログを閉じる処理(`cancelDelete`)が先に走るため、範囲は確定ボタンから受け取る。
    public func confirmDelete(_ scope: DataDeletionScope) async {
        guard !isBusy else { return }
        pendingDeletion = nil
        isDeleting = true
        defer { isDeleting = false }
        let target: ExamID? = scope == .exam ? examID : nil
        do {
            try await dataManagement.deleteAll(examID: target)
            try await reports.removeAll(examID: target)
        } catch {
            self.error = String(localized: "settings.deleteFailed", bundle: .module)
            return
        }
        error = nil
        await onDeleted(target)
    }
}
