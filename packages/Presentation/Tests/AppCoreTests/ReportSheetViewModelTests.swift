import Foundation
import Testing
import AppCore
import SettingsFeature
import DomainModels
import DomainInterfaces
import DomainTestSupport

@MainActor struct ReportSheetViewModelTests {
    private let context = QuestionReportContext(examID: "test-alpha", questionID: "Q-3.2-0147", questionRevision: 2, packVersion: "1.2.0")
    private let metadata = ReportMetadata(appVersion: "1.0.3", locale: "ja-JP")
    private let now = Date(timeIntervalSince1970: 1_793_491_200)
    private let reportID = UUID(uuidString: "00000000-0000-0000-0000-000000000015")!

    private func makeModel(queue: ReportQueueFake = ReportQueueFake(), sender: (any ReportSending)? = nil) -> ReportSheetViewModel {
        let id = reportID
        return ReportSheetViewModel(context: context, queue: queue, sender: sender, metadata: metadata,
                                    time: FixedTimeSource(now), makeID: { id })
    }

    @Test func reasonsAreSelectable() {
        // Act
        let model = makeModel()
        // Assert: BDD 7.2 の6種類を API と同じ順で並べ、未選択では送信できない
        #expect(ReportSheetViewModel.reasons == [.wrongAnswer, .unclearStem, .typo, .outdated, .brokenLink, .other])
        #expect(ReportSheetViewModel.reasons.map(\.rawValue) == ["wrongAnswer", "unclearStem", "typo", "outdated", "brokenLink", "other"])
        #expect(Set(ReportSheetViewModel.reasons.map(ReportSheetViewModel.title(of:))).count == 6)
        #expect(!model.canSubmit)
        model.reason = .typo
        #expect(model.canSubmit)
    }

    @Test func commentLimit() {
        // Arrange
        let model = makeModel()
        model.reason = .other
        // Act / Assert: 501 文字は送信できず、残りは -1
        model.comment = String(repeating: "あ", count: 501)
        #expect(!model.canSubmit)
        #expect(model.remainingCharacters == -1)
        #expect(model.isCommentTooLong)
        // 500 文字ちょうどは送信できる。絵文字の結合文字も 1 文字として数える
        model.comment = String(repeating: "👨‍👩‍👧", count: 500)
        #expect(model.canSubmit)
        #expect(model.remainingCharacters == 0)
    }

    @Test func privacyNoticeShown() {
        #expect(makeModel().privacyNotice == "氏名・メールアドレスなどの個人情報は書かないでください")
    }

    @Test func enqueueContainsContext() async throws {
        // Arrange
        let queue = ReportQueueFake()
        let model = makeModel(queue: queue)
        model.reason = .wrongAnswer
        model.comment = "  B ではなく C が正しいのでは\n"
        // Act
        await model.submit()
        // Assert: C-11 の文脈と理由・前後空白を除いたコメント。送信の仕組みがないので受付のみ
        let entry = PendingReportEntry(id: reportID, examID: "test-alpha", questionID: "Q-3.2-0147", questionRevision: 2,
                                       packVersion: "1.2.0", reason: .wrongAnswer, comment: "B ではなく C が正しいのでは",
                                       appVersion: "1.0.3", locale: "ja-JP", createdAt: now)
        #expect(try await queue.pending(examID: nil) == [entry])
        #expect(model.outcome == .queued)
        #expect(model.message == "報告を受け付けました。あとで送信します")
        #expect(!model.canSubmit)
    }

    @Test func offlineMessage() async throws {
        // Arrange: -network offline 相当
        let queue = ReportQueueFake()
        let model = makeModel(queue: queue, sender: ReportSenderFake(outcome: .offline))
        model.reason = .outdated
        // Act
        await model.submit()
        // Assert: E-08 の文言を出し、キューに残す
        #expect(model.outcome == .offline)
        #expect(model.message == "オフラインのため、あとで送信します")
        #expect(try await queue.pending(examID: nil).map(\.id) == [reportID])
    }

    @Test func sentReportLeavesQueue() async throws {
        let queue = ReportQueueFake()
        let sender = ReportSenderFake(outcome: .sent)
        let model = makeModel(queue: queue, sender: sender)
        model.reason = .brokenLink
        await model.submit()
        #expect(model.outcome == .sent)
        #expect(try await queue.pending(examID: nil).isEmpty)
        #expect(await sender.sentIDs == [reportID])
    }

    @Test func saveFailureCanRetry() async throws {
        // Arrange
        let queue = ReportQueueFake(failEnqueue: true)
        let model = makeModel(queue: queue)
        model.reason = .typo
        // Act
        await model.submit()
        // Assert: 保存できなければ受付済みにせず、再試行できる
        #expect(model.outcome == nil)
        #expect(model.error == "報告を保存できませんでした。もう一度お試しください")
        #expect(model.canSubmit)
        await queue.setFailEnqueue(false)
        await model.submit()
        #expect(model.outcome == .queued)
        #expect(model.error == nil)
    }

    @Test func rejectsDuplicateSubmit() async throws {
        // Arrange: 保存の完了を待たせ、その間に2回目を押す
        let queue = ReportQueueFake(holdEnqueue: true)
        let model = makeModel(queue: queue)
        model.reason = .other
        // Act
        let first = Task { await model.submit() }
        while !(await queue.isHolding) { await Task.yield() }
        #expect(model.isSubmitting)
        #expect(!model.canSubmit)
        await model.submit()
        await queue.release()
        await first.value
        // Assert
        #expect(try await queue.pending(examID: nil).count == 1)
        #expect(model.outcome == .queued)
    }
}

private actor ReportQueueFake: ReportQueue {
    private var entries: [PendingReportEntry] = []
    private var failEnqueue: Bool
    private let holdEnqueue: Bool
    private var continuation: CheckedContinuation<Void, Never>?
    var isHolding: Bool { continuation != nil }

    init(failEnqueue: Bool = false, holdEnqueue: Bool = false) { self.failEnqueue = failEnqueue; self.holdEnqueue = holdEnqueue }
    func setFailEnqueue(_ value: Bool) { failEnqueue = value }
    func release() { continuation?.resume(); continuation = nil }

    func enqueue(_ entry: PendingReportEntry) async throws(PersistenceError) {
        if holdEnqueue { await withCheckedContinuation { continuation = $0 } }
        guard !failEnqueue else { throw .saveFailed("fake") }
        entries.append(entry)
    }
    func pending(examID: ExamID?) throws(PersistenceError) -> [PendingReportEntry] { entries.filter { examID == nil || $0.examID == examID } }
    func remove(ids: Set<UUID>) throws(PersistenceError) { entries.removeAll { ids.contains($0.id) } }
    func removeAll(examID: ExamID?) throws(PersistenceError) { entries.removeAll { examID == nil || $0.examID == examID } }
}

private actor ReportSenderFake: ReportSending {
    let outcome: ReportSendOutcome
    private(set) var sentIDs: [UUID] = []
    init(outcome: ReportSendOutcome) { self.outcome = outcome }
    func send(_ entry: PendingReportEntry) -> ReportSendOutcome {
        if outcome == .sent { sentIDs.append(entry.id) }
        return outcome
    }
}
