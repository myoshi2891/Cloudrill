import Foundation
import Testing
import AppCore
import ExamFeature
import SettingsFeature
import DomainModels
import DomainInterfaces
import DomainTestSupport
import StudyModels

@MainActor struct SettingsViewModelTests {
    private struct Harness {
        let model: SettingsViewModel
        let settings: SettingsStore
        let data: DataManagementSpy
        let reports: ReportRemovalSpy
        let deleted: DeletedSpy
        let directory: URL
    }

    private func harness(settings: SettingsStore = SettingsStore(), data: DataManagementSpy = DataManagementSpy(),
                         vendors: [Vendor] = []) -> Harness {
        let reports = ReportRemovalSpy(), deleted = DeletedSpy()
        let directory = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)
        let model = SettingsViewModel(examID: "test-alpha", examName: "ALPHA", vendors: vendors, appVersion: "1.0.0",
            settings: settings, dataManagement: data, reports: reports, time: FixedTimeSource(SelectionFixtures.now),
            exportDirectory: directory, timeZone: TimeZone(identifier: "UTC")!,
            onDeleted: { examID in deleted.calls.append(examID) })
        return Harness(model: model, settings: settings, data: data, reports: reports, deleted: deleted, directory: directory)
    }

    @Test func editsExamPreference() async throws {
        // Arrange
        let h = harness()
        await h.model.load()
        // Act
        await h.model.setDailyNewCards(30)
        // Assert: 選択中の試験だけが変わる
        #expect(h.model.preference.dailyNewCards == 30)
        #expect(await h.settings.preferences["test-alpha"]?.dailyNewCards == 30)
        #expect(await h.settings.preferences["test-beta"] == nil)
        #expect(try await h.settings.preference(examID: "test-beta") == .default)
    }

    @Test func preferenceSaveFailureRestoresValue() async throws {
        let settings = SettingsStore()
        let h = harness(settings: settings)
        await h.model.load()
        await settings.rejectSaves()
        await h.model.setDailyReviewLimit(300)
        #expect(h.model.preference.dailyReviewLimit == ExamPreference.default.dailyReviewLimit)
        #expect(h.model.error == "設定を保存できませんでした。もう一度お試しください")
    }

    @Test func shuffleSetting() async throws {
        // Arrange: シャッフル OFF で模試を開始済み
        let settings = SettingsStore(user: UserSettings(currentExamID: "test-alpha", shuffleChoices: false))
        let running = StartAttempts()
        let first = try startExam(settings: settings, attempts: running)
        await first.start()
        let before = try #require(await running.current)
        #expect(before.snapshot.order.items.first?.choiceIDs == ["a", "b", "c", "d"])
        let h = harness(settings: settings)
        await h.model.load()
        // Act
        await h.model.setShuffleChoices(true)
        // Assert: 他の設定は保持し、進行中の模試の並びは変わらない
        #expect(await settings.user.shuffleChoices)
        #expect(await settings.user.currentExamID == "test-alpha")
        let reopened = try startExam(settings: settings, attempts: running)
        await reopened.start()
        #expect(await running.current == before)
        // 以後に開始する模試には反映される
        let next = StartAttempts()
        await (try startExam(settings: settings, attempts: next)).start()
        let order = try #require(await next.current?.snapshot.order.items.first?.choiceIDs)
        #expect(order.sorted() == ["a", "b", "c", "d"])
        #expect(order != ["a", "b", "c", "d"])
    }

    @Test func exportData() async throws {
        // Arrange
        let payload = Data("{\"version\":1}".utf8)
        let h = harness(data: DataManagementSpy(exported: payload))
        defer { try? FileManager.default.removeItem(at: h.directory) }
        try FileManager.default.createDirectory(at: h.directory, withIntermediateDirectories: true)
        // Act
        await h.model.exportData()
        // Assert: 全試験を書き出し、共有シートに渡すファイルを作る
        let file = try #require(h.model.exportFile)
        #expect(file.lastPathComponent == "cloudrill-export-20270115.json")
        #expect(try Data(contentsOf: file) == payload)
        #expect(await h.data.exportedScopes == [nil])
    }

    @Test func exportFailureShowsError() async throws {
        let h = harness(data: DataManagementSpy(failExport: true))
        await h.model.exportData()
        #expect(h.model.exportFile == nil)
        #expect(h.model.error == "データを書き出せませんでした。もう一度お試しください")
    }

    @Test func failedReexportKeepsPreviousFileTracked() async throws {
        // Arrange: 1 回目の書き出しに成功し、ファイルが残っている
        let h = harness(data: DataManagementSpy(exported: Data("{\"version\":1}".utf8)))
        defer { try? FileManager.default.removeItem(at: h.directory) }
        try FileManager.default.createDirectory(at: h.directory, withIntermediateDirectories: true)
        await h.model.exportData()
        let file = try #require(h.model.exportFile)
        // Act: 2 回目の書き出しが失敗する
        await h.data.setFailExport(true)
        await h.model.exportData()
        // Assert: 前のファイルの参照が残り、削除の確定でファイルが消える
        #expect(h.model.exportFile == file)
        #expect(h.model.error == "データを書き出せませんでした。もう一度お試しください")
        await h.model.confirmDelete(.exam)
        #expect(!FileManager.default.fileExists(atPath: file.path(percentEncoded: false)))
        #expect(h.model.exportFile == nil)
    }

    @Test(arguments: [(DataDeletionScope.exam, ExamID?.some("test-alpha")), (.all, nil)])
    func deleteRequiresConfirmation(scope: DataDeletionScope, expected: ExamID?) async throws {
        // Arrange
        let h = harness()
        // Act: 要求(確認ダイアログの表示)とキャンセルでは削除しない
        h.model.requestDelete(scope)
        #expect(h.model.pendingDeletion == scope)
        h.model.cancelDelete()
        #expect(h.model.pendingDeletion == nil)
        #expect(await h.data.deletedScopes.isEmpty)
        // 確定したときだけ、学習データと報告キューを同じ範囲で削除する。
        // ダイアログは確定ボタンの処理より先に閉じる(cancelDelete が走る)ので、その順序で確認する
        h.model.requestDelete(scope)
        h.model.cancelDelete()
        await h.model.confirmDelete(scope)
        // Assert
        #expect(await h.data.deletedScopes == [expected])
        #expect(await h.reports.removedScopes == [expected])
        #expect(h.deleted.calls == [expected])
        #expect(h.model.pendingDeletion == nil)
    }

    @Test(arguments: [(DataDeletionScope.exam, ExamID?.some("test-alpha")), (.all, nil)])
    func deleteRemovesOutstandingExport(scope: DataDeletionScope, expected: ExamID?) async throws {
        // Arrange: 全試験を含む書き出しファイルが、共有の完了前で残っている
        let h = harness(data: DataManagementSpy(exported: Data("{\"exams\":[\"test-alpha\",\"test-beta\"]}".utf8)))
        defer { try? FileManager.default.removeItem(at: h.directory) }
        try FileManager.default.createDirectory(at: h.directory, withIntermediateDirectories: true)
        await h.model.exportData()
        let file = try #require(h.model.exportFile)
        await h.data.watch(file)
        // Act
        await h.model.confirmDelete(scope)
        // Assert: 最初のストアの削除が始まった時点で、書き出しファイルはもう無い
        #expect(await h.data.watchedFileExistedOnDelete == [false])
        // 書き出しファイルは残らない。学習データは指定した範囲だけを削除し、ほかの試験は対象にしない
        #expect(!FileManager.default.fileExists(atPath: file.path(percentEncoded: false)))
        #expect(h.model.exportFile == nil)
        #expect(try FileManager.default.contentsOfDirectory(atPath: h.directory.path(percentEncoded: false)).isEmpty)
        #expect(await h.data.deletedScopes == [expected])
        #expect(await h.reports.removedScopes == [expected])
        #expect(h.deleted.calls == [expected])
    }

    @Test func deleteRemovesExportFromEarlierSheet() async throws {
        // Arrange: 前に開いたシート(別の ViewModel)が書き出したファイルが残っている
        let earlier = harness(data: DataManagementSpy(exported: Data("{\"version\":1}".utf8)))
        defer { try? FileManager.default.removeItem(at: earlier.directory) }
        try FileManager.default.createDirectory(at: earlier.directory, withIntermediateDirectories: true)
        await earlier.model.exportData()
        let file = try #require(earlier.model.exportFile)
        let data = DataManagementSpy()
        await data.watch(file)
        let reports = ReportRemovalSpy(), deleted = DeletedSpy()
        let current = SettingsViewModel(examID: "test-alpha", examName: "ALPHA", vendors: [], appVersion: "1.0.0",
            settings: SettingsStore(), dataManagement: data, reports: reports, time: FixedTimeSource(SelectionFixtures.now),
            exportDirectory: earlier.directory, timeZone: TimeZone(identifier: "UTC")!,
            onDeleted: { examID in deleted.calls.append(examID) })
        // Act: 新しく開いたシートで削除を確定する
        await current.confirmDelete(.all)
        // Assert: 参照を持たないファイルも、ストアの削除の前に消える
        #expect(await data.watchedFileExistedOnDelete == [false])
        #expect(!FileManager.default.fileExists(atPath: file.path(percentEncoded: false)))
        #expect(deleted.calls == [nil])
    }

    @Test func exportStartedBeforeCompletedDeletionIsDiscarded() async throws {
        // Arrange: 1 つ目のシートの書き出しを、学習データの読み取り中に止める
        let earlier = harness(data: DataManagementSpy(exported: Data("{\"version\":1}".utf8)))
        defer { try? FileManager.default.removeItem(at: earlier.directory) }
        try FileManager.default.createDirectory(at: earlier.directory, withIntermediateDirectories: true)
        await earlier.data.holdNextExport()
        let export = Task { await earlier.model.exportData() }
        while await !earlier.data.isExportHeld { await Task.yield() }
        let current = SettingsViewModel(examID: "test-alpha", examName: "ALPHA", vendors: [], appVersion: "1.0.0",
            settings: SettingsStore(), dataManagement: DataManagementSpy(), reports: ReportRemovalSpy(),
            time: FixedTimeSource(SelectionFixtures.now), exportDirectory: earlier.directory,
            timeZone: TimeZone(identifier: "UTC")!, onDeleted: { _ in })
        // Act: 2 つ目のシートで削除を最後まで終えて(削除中ではない状態に戻って)から、書き出しを再開する
        await current.confirmDelete(.all)
        #expect(current.error == nil)
        await earlier.data.resumeExport()
        await export.value
        // Assert: 世代が変わったので、削除前のデータを含みうるファイルを書かない
        #expect(earlier.model.error == "データを書き出せませんでした。もう一度お試しください")
        #expect(earlier.model.exportFile == nil)
        #expect(try FileManager.default.contentsOfDirectory(atPath: earlier.directory.path(percentEncoded: false)).isEmpty)
    }

    @Test func exportRemovalFailureStopsDeletionAndAllowsRetry() async throws {
        // Arrange: 書き出しファイルがあり、ディレクトリを読み取り専用にして削除を失敗させる
        let h = harness(data: DataManagementSpy(exported: Data("{\"version\":1}".utf8)))
        defer {
            try? FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: h.directory.path(percentEncoded: false))
            try? FileManager.default.removeItem(at: h.directory)
        }
        try FileManager.default.createDirectory(at: h.directory, withIntermediateDirectories: true)
        await h.model.exportData()
        let file = try #require(h.model.exportFile)
        try FileManager.default.setAttributes([.posixPermissions: 0o555], ofItemAtPath: h.directory.path(percentEncoded: false))
        // Act
        await h.model.confirmDelete(.all)
        // Assert: どちらのストアも削除せず、完了の処理も呼ばない
        #expect(h.model.error == "データを削除できませんでした。もう一度お試しください")
        #expect(await h.data.deletedScopes.isEmpty)
        #expect(await h.reports.removedScopes.isEmpty)
        #expect(h.deleted.calls.isEmpty)
        #expect(FileManager.default.fileExists(atPath: file.path(percentEncoded: false)))
        // Act: 削除できる状態に戻して、もう一度確定する
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: h.directory.path(percentEncoded: false))
        await h.model.confirmDelete(.all)
        // Assert
        #expect(!FileManager.default.fileExists(atPath: file.path(percentEncoded: false)))
        #expect(await h.data.deletedScopes == [nil])
        #expect(await h.reports.removedScopes == [nil])
        #expect(h.deleted.calls == [nil])
        #expect(h.model.error == nil)
    }

    @Test func deleteFailureDoesNotFinish() async throws {
        let h = harness(data: DataManagementSpy(failDelete: true))
        h.model.requestDelete(.all)
        await h.model.confirmDelete(.all)
        #expect(h.deleted.calls.isEmpty)
        #expect(await h.reports.removedScopes.isEmpty)
        #expect(h.model.error == "データを削除できませんでした。もう一度お試しください")
    }

    @Test func aboutShowsNotices() async throws {
        let vendors = [try SelectionFixtures.content("test-alpha").vendor, try SelectionFixtures.content("test-beta").vendor]
        let h = harness(vendors: vendors)
        #expect(h.model.vendors.map(\.trademarkNotice) == vendors.map(\.trademarkNotice))
        #expect(h.model.unofficialNotice.contains("非公式"))
        #expect(h.model.noGuaranteeNotice.contains("合格を保証するものではありません"))
    }

    private func startExam(settings: SettingsStore, attempts: StartAttempts) throws -> ExamStartViewModel {
        ExamStartViewModel(content: try ExamFixture("test-alpha"), examSet: 1, attempts: attempts, pins: TestPins(),
                           settings: settings, time: FixedTimeSource(SelectionFixtures.now), seedProvider: { 42 }, router: AppRouter())
    }
}

private actor SettingsStore: SettingsRepository {
    var user: UserSettings
    var preferences: [ExamID: ExamPreference] = [:]
    private var failSave = false
    init(user: UserSettings = UserSettings(currentExamID: "test-alpha")) { self.user = user }
    func rejectSaves() { failSave = true }
    func settings() throws(PersistenceError) -> UserSettings { user }
    func preference(examID: ExamID) throws(PersistenceError) -> ExamPreference { preferences[examID] ?? .default }
    func save(settings: UserSettings, at date: Date) throws(PersistenceError) {
        guard !failSave else { throw .saveFailed("test") }
        user = settings
    }
    func save(preference: ExamPreference, examID: ExamID, at date: Date) throws(PersistenceError) {
        guard !failSave else { throw .saveFailed("test") }
        preferences[examID] = preference
    }
}

private actor DataManagementSpy: DataManagementRepository {
    private let exported: Data
    private var failExport: Bool
    private let failDelete: Bool
    private(set) var exportedScopes: [ExamID?] = []
    private(set) var deletedScopes: [ExamID?] = []
    private var watched: URL?
    /// deleteAll が呼ばれた時点で、watch したファイルが存在したか
    private(set) var watchedFileExistedOnDelete: [Bool] = []
    init(exported: Data = Data(), failExport: Bool = false, failDelete: Bool = false) {
        self.exported = exported; self.failExport = failExport; self.failDelete = failDelete
    }
    private var holdExport = false
    private var heldExport: CheckedContinuation<Void, Never>?
    var isExportHeld: Bool { heldExport != nil }
    func setFailExport(_ value: Bool) { failExport = value }
    func watch(_ file: URL) { watched = file }
    /// 次の export を、resumeExport() まで止める
    func holdNextExport() { holdExport = true }
    func resumeExport() { heldExport?.resume(); heldExport = nil }
    func export(examID: ExamID?) async throws(PersistenceError) -> Data {
        if holdExport {
            holdExport = false
            await withCheckedContinuation { heldExport = $0 }
        }
        guard !failExport else { throw .corrupted("test") }
        exportedScopes.append(examID)
        return exported
    }
    func deleteAll(examID: ExamID?) throws(PersistenceError) {
        if let watched { watchedFileExistedOnDelete.append(FileManager.default.fileExists(atPath: watched.path(percentEncoded: false))) }
        guard !failDelete else { throw .saveFailed("test") }
        deletedScopes.append(examID)
    }
}

private actor ReportRemovalSpy: ReportQueue {
    private(set) var removedScopes: [ExamID?] = []
    func enqueue(_ entry: PendingReportEntry) throws(PersistenceError) {}
    func pending(examID: ExamID?) throws(PersistenceError) -> [PendingReportEntry] { [] }
    func remove(ids: Set<UUID>) throws(PersistenceError) {}
    func removeAll(examID: ExamID?) throws(PersistenceError) { removedScopes.append(examID) }
}

@MainActor private final class DeletedSpy { var calls: [ExamID?] = [] }
