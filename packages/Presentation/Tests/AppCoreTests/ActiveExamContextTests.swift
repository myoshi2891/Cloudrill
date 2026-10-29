import Foundation
import Testing
import DomainModels
import DomainInterfaces
import DomainTestSupport
import AppCore
import HomeFeature

@MainActor struct ActiveExamContextTests {
    private func make(ids: [ExamID] = ["test-alpha", "test-beta"], settings: SelectionSettings = SelectionSettings(),
                      attempts: SelectionAttempts = SelectionAttempts(), failures: Set<ExamID> = []) throws -> ActiveExamContext {
        let available = try Dictionary(uniqueKeysWithValues: ids.map { ($0, try SelectionFixtures.content($0) as any ExamContentProvider) })
        return ActiveExamContext(available: available, catalog: try (ids + Array(failures)).map { try SelectionFixtures.entry($0) },
                                 failures: failures, settings: settings, attempts: attempts,
                                 time: FixedTimeSource(SelectionFixtures.now), router: AppRouter())
    }

    @Test func restoresLastExam() async throws {
        let context = try make(settings: SelectionSettings(current: "test-beta"))
        await context.restore()
        #expect(context.state.examID == "test-beta")
        #expect(context.content?.definition.shortName == "BETA")
        #expect(!context.state.needsSelection)
    }
    @Test func singleExamAutoSelectedAndSaved() async throws {
        let settings = SelectionSettings(), context = try make(ids: ["test-alpha"], settings: settings)
        await context.restore()
        #expect(context.state.examID == "test-alpha")
        #expect(await settings.value.currentExamID == "test-alpha")
        #expect(await settings.savedAt == SelectionFixtures.now)
    }
    @Test func multipleExamsShowPicker() async throws {
        let context = try make()
        await context.restore()
        #expect(context.state.needsSelection && context.state.examID == nil)
    }
    @Test func unavailableLastExamDoesNotSilentlySelectAnother() async throws {
        let context = try make(ids: ["test-beta"], settings: SelectionSettings(current: "test-alpha"), failures: ["test-alpha"])
        await context.restore()
        #expect(context.state.needsSelection && context.state.examID == nil)
        #expect(context.state.alert == .examUnavailable)
    }
    @Test func noExamAvailableIsFatal() async throws {
        let context = try make(ids: [])
        await context.restore()
        #expect(context.state.fatal == .contentLoadFailed)
    }
    @Test func switchSuspendsAttemptPreservesSettingsAndResetsNavigation() async throws {
        let settings = SelectionSettings(current: "test-alpha")
        let initial = try SelectionFixtures.attempt(), attempts = SelectionAttempts(initial)
        let context = try make(settings: settings, attempts: attempts)
        await context.restore()
        context.router.open(.examSession(attemptID: initial.id))
        await context.switchExam(to: "test-beta")
        #expect(context.state.examID == "test-beta")
        #expect(await attempts.current?.snapshot.state == .suspended)
        #expect(await attempts.current?.snapshot.timer?.deadline == initial.snapshot.timer?.deadline)
        let saved = await settings.value
        #expect(saved.currentExamID == "test-beta" && saved.displayLanguage == .en && saved.shuffleChoices)
        #expect(context.router.path(for: .exam).isEmpty && context.router.selectedTab == .home)
    }
    @Test(arguments: [false, true]) func failureKeepsActiveExamAndNavigation(failAttemptSave: Bool) async throws {
        let initial = try SelectionFixtures.attempt()
        let settings = SelectionSettings(current: "test-alpha"), attempts = SelectionAttempts(initial)
        let context = try make(settings: settings, attempts: attempts)
        await context.restore()
        context.router.open(.examStart(examSet: 1))
        if failAttemptSave { await attempts.rejectSaves() } else { await settings.rejectSaves() }
        await context.switchExam(to: "test-beta")
        #expect(context.state.examID == "test-alpha")
        #expect(context.state.alert == .persistenceFailed)
        #expect(await settings.value.currentExamID == "test-alpha")
        // 切り替えに失敗したら、旧試験の受験を中断したまま残さない。
        #expect(await attempts.current?.snapshot == initial.snapshot)
        #expect(context.router.path(for: .exam) == [.examStart(examSet: 1)])
    }
    @Test func repeatedRestoreDoesNotDiscardNavigation() async throws {
        let context = try make(ids: ["test-alpha"])
        await context.restore()
        context.router.open(.docsIndex(domain: nil))
        await context.restore()
        #expect(context.router.path(for: .learn) == [.docsIndex(domain: nil)])
    }
    @Test func pickerDisablesComingSoonAndShowsTrademark() async throws {
        let alpha = try SelectionFixtures.content("test-alpha")
        let context = ActiveExamContext(available: ["test-alpha": alpha],
            catalog: try [SelectionFixtures.entry("test-alpha"), SelectionFixtures.entry("test-beta", status: .comingSoon)],
            failures: [], settings: SelectionSettings(), attempts: SelectionAttempts(),
            time: FixedTimeSource(SelectionFixtures.now), router: AppRouter())
        await context.restore()
        let picker = ExamPickerViewModel(context: context)
        #expect(picker.state.items.map(\.isSelectable) == [true, false])
        #expect(picker.state.items.last?.status == .comingSoon)
        #expect(picker.state.trademarkNotice == alpha.vendor.trademarkNotice)
        await picker.select("test-beta")
        #expect(context.state.examID == "test-alpha")
    }

    @Test func concurrentSwitchDoesNotOverwritePendingSelection() async throws {
        let settings = SelectionSettings(current: "test-alpha")
        let alpha = try SelectionFixtures.content("test-alpha"), beta = try SelectionFixtures.content("test-beta")
        var definition = beta.definition
        definition.id = "test-gamma"
        let gamma = StubContent(definition: definition, vendor: beta.vendor)
        let context = ActiveExamContext(available: ["test-alpha": alpha, "test-beta": beta, "test-gamma": gamma],
            catalog: try ["test-alpha", "test-beta", "test-gamma"].map { try SelectionFixtures.entry($0) },
            failures: [], settings: settings, attempts: SelectionAttempts(),
            time: FixedTimeSource(SelectionFixtures.now), router: AppRouter())
        await context.restore()
        await settings.pauseNextRead()
        let first = Task { await context.switchExam(to: "test-beta") }
        await settings.waitForPausedRead()
        #expect(context.state.isLoading)
        await context.switchExam(to: "test-gamma")
        await settings.resumeRead()
        await first.value
        #expect(context.state.examID == "test-beta")
        #expect(await settings.value.currentExamID == "test-beta")
        #expect(!context.state.isLoading)
    }

    @Test func failedAndUninstalledRetiredExamsCannotBeSelected() async throws {
        let alpha = try SelectionFixtures.content("test-alpha"), beta = try SelectionFixtures.content("test-beta")
        let context = ActiveExamContext(available: ["test-alpha": alpha, "test-beta": beta],
            catalog: try [SelectionFixtures.entry("test-alpha"), SelectionFixtures.entry("test-beta", status: .retired)],
            failures: ["test-beta"], settings: SelectionSettings(), attempts: SelectionAttempts(),
            time: FixedTimeSource(SelectionFixtures.now), router: AppRouter())
        await context.restore()
        #expect(ExamPickerViewModel(context: context).state.items.map(\.id) == ["test-alpha"])
        await context.switchExam(to: "test-beta")
        #expect(context.state.examID == "test-alpha" && context.state.alert == .examUnavailable)
    }
}
