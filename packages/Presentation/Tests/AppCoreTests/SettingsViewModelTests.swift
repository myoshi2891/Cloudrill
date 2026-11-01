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
    private let failExport: Bool
    private let failDelete: Bool
    private(set) var exportedScopes: [ExamID?] = []
    private(set) var deletedScopes: [ExamID?] = []
    init(exported: Data = Data(), failExport: Bool = false, failDelete: Bool = false) {
        self.exported = exported; self.failExport = failExport; self.failDelete = failDelete
    }
    func export(examID: ExamID?) throws(PersistenceError) -> Data {
        guard !failExport else { throw .corrupted("test") }
        exportedScopes.append(examID)
        return exported
    }
    func deleteAll(examID: ExamID?) throws(PersistenceError) {
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
