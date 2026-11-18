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

/// 設定のシートは開くたびに ViewModel を作り直すので、書き出しと削除の調整はインスタンスをまたいで共有する。
/// 削除を確定すると、書き出し先のディレクトリごとに世代を進める。書き出しは開始時の世代を覚え、
/// 書き込みの直前(MainActor 上で同期的に)に世代と削除中かを確かめ、変わっていれば書き込まない。
@MainActor enum ExportDeletionGuard {
    private static var generations: [String: Int] = [:]
    private static var deleting: [String: Int] = [:]
    static func generation(_ directory: URL) -> Int { generations[key(directory), default: 0] }
    static func isDeleting(_ directory: URL) -> Bool { deleting[key(directory), default: 0] > 0 }
    static func beginDeletion(_ directory: URL) {
        generations[key(directory), default: 0] += 1
        deleting[key(directory), default: 0] += 1
    }
    static func endDeletion(_ directory: URL) {
        generations[key(directory), default: 0] += 1
        deleting[key(directory), default: 0] -= 1
    }
    private static func key(_ directory: URL) -> String { directory.standardizedFileURL.path(percentEncoded: false) }
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
        // 削除の途中(別のシートの ViewModel を含む)では書き出さない
        guard !ExportDeletionGuard.isDeleting(exportDirectory) else {
            error = String(localized: "settings.exportFailed", bundle: .module)
            return
        }
        let generation = ExportDeletionGuard.generation(exportDirectory)
        isExporting = true
        defer { isExporting = false }
        // 失敗しても前のファイルの参照は残す(削除の確定で消すため)。参照を外すのは、
        // 前のファイルを消せたときか、新しいファイルの書き出しに成功したときだけ
        do {
            let data = try await dataManagement.export(examID: nil)
            let url = exportDirectory.appending(path: exportFileName())
            // 名前が同じなら atomic な書き込みで置き換わる。違えば(日付が変わった)、前のファイルを先に消す
            if let previous = exportFile, previous != url { try removeExportFile() }
            // 書き出しの読み取り中に削除が始まった(または終わった)なら、削除した学習データを含みうるので書かない。
            // 確認と書き込みのあいだに await を挟まないので、MainActor 上の削除と入れ替わらない
            guard ExportDeletionGuard.generation(exportDirectory) == generation,
                  !ExportDeletionGuard.isDeleting(exportDirectory) else {
                self.error = String(localized: "settings.exportFailed", bundle: .module)
                return
            }
            try data.write(to: url, options: .atomic)
            exportFile = url; error = nil
        } catch {
            self.error = String(localized: "settings.exportFailed", bundle: .module)
        }
    }

    private static let exportFilePrefix = "cloudrill-export-"

    private func exportFileName() -> String {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = timeZone
        let parts = calendar.dateComponents([.year, .month, .day], from: time.now())
        return String(format: Self.exportFilePrefix + "%04d%02d%02d.json", parts.year ?? 0, parts.month ?? 0, parts.day ?? 0)
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
        // 進行中の書き出し(前に開いたシートのものを含む)が、削除のあとにファイルを書かないようにする
        ExportDeletionGuard.beginDeletion(exportDirectory)
        defer {
            ExportDeletionGuard.endDeletion(exportDirectory)
            isDeleting = false
        }
        let target: ExamID? = scope == .exam ? examID : nil
        do {
            // 書き出したファイルは全試験のデータを含むので、試験を指定した削除でも消す。
            // 前に開いたシートが書き出したファイルも、このインスタンスは参照を持たないので、名前の形で探して消す。
            // 消せなければ、学習データを消す前に失敗として扱う(SEC-04-08、SEC-04-09)
            try removeExportFile()
            try removeOutstandingExports()
            try await dataManagement.deleteAll(examID: target)
            try await reports.removeAll(examID: target)
        } catch {
            self.error = String(localized: "settings.deleteFailed", bundle: .module)
            return
        }
        error = nil
        await onDeleted(target)
    }

    /// 書き出し先にある、このアプリの書き出しファイル(`cloudrill-export-*.json`)をすべて消す。
    /// ディレクトリやファイルが無いことは削除できた場合と同じに扱い、ほかの失敗は投げる。
    private func removeOutstandingExports() throws {
        let names: [String]
        do {
            names = try FileManager.default.contentsOfDirectory(atPath: exportDirectory.path(percentEncoded: false))
        } catch let error as CocoaError where error.code == .fileReadNoSuchFile || error.code == .fileNoSuchFile {
            return
        }
        for name in names where name.hasPrefix(Self.exportFilePrefix) && name.hasSuffix(".json") {
            do {
                try FileManager.default.removeItem(at: exportDirectory.appending(path: name))
            } catch let error as CocoaError where error.code == .fileNoSuchFile {
                // すでに消えている
            }
        }
    }

    private func removeExportFile() throws {
        guard let file = exportFile else { return }
        // 存在の確認と削除の間に状態が変わりうるので、削除を直接試す。
        // 無視するのは「ファイルが無い」ことが確かな場合だけで、ほかの失敗は参照を残したまま投げる
        do {
            try FileManager.default.removeItem(at: file)
        } catch let error as CocoaError where error.code == .fileNoSuchFile {
            // すでに消えているので、削除できた場合と同じに扱う
        }
        exportFile = nil
    }
}
