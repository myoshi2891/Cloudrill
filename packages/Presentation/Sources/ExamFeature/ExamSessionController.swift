import Foundation
import Observation
import OSLog
import DomainModels
import DomainInterfaces
import StudyModels
import ExamEngine

/// 保存・状態遷移・時計を管理する。SwiftUI や画面遷移には依存しない。
@MainActor @Observable final class ExamSessionController {
    private(set) var session: ExamSession?
    private(set) var questions: [Question] = []
    private(set) var cases: [CaseStudy] = []
    private(set) var isBusy = false
    private(set) var alert: String?
    private(set) var remainingSeconds = 0
    private(set) var warning: ExamSessionWarning?
    private(set) var feedbackCount = 0
    private(set) var submissionComplete = false
    private let examID: ExamID
    private let attemptID: UUID
    private let resolver: any ExamContentResolving
    private let attempts: any ExamAttemptRepository
    private let pins: any PackPinning
    private let time: any TimeSource
    private let evaluators: AnswerEvaluatorRegistry
    private let policy = ExamTimerPolicy()
    private var definition: ExamDefinition?
    private var previousTick: Date?
    private var questionEnteredAt: Date?
    private let submission: ExamSubmission
    private var reviewVisible = false
    private var wantsActive = true

    init(examID: ExamID, attemptID: UUID, resolver: any ExamContentResolving,
         attempts: any ExamAttemptRepository, pins: any PackPinning, cards: any CardStateRepository,
         settings: any SettingsRepository, time: any TimeSource,
         evaluators: AnswerEvaluatorRegistry) {
        self.examID = examID; self.attemptID = attemptID; self.resolver = resolver
        self.attempts = attempts; self.pins = pins; self.time = time; self.evaluators = evaluators
        submission = ExamSubmission(attempts: attempts, pins: pins, cards: cards, settings: settings, evaluators: evaluators)
    }

    func load() async {
        await run(errorKey: "session.loadFailed") {
            if self.session != nil { return }
            guard let attempt = try await self.attempts.inProgress(examID: self.examID), attempt.id == self.attemptID else {
                throw PersistenceError.notFound
            }
            let content = try await self.resolver.content(for: self.examID, version: attempt.packVersion)
            guard content.definition.id == self.examID, content.packVersion == attempt.packVersion else {
                throw ContentError.storage("attempt pack mismatch")
            }
            try await self.pins.pin(attempt.packVersion, for: self.examID, attemptID: self.attemptID)
            let ids = attempt.snapshot.order.items.map(\.questionID)
            let loaded = try await content.questions(ids: ids)
            let byID = Dictionary(loaded.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
            guard !ids.isEmpty, Set(ids).count == ids.count, loaded.count == ids.count else {
                throw ContentError.storage("invalid exam questions")
            }
            try ExamOrderBuilder.validate(attempt.snapshot.order, against: byID)
            let cases = content.definition.features.caseStudies ? try await content.caseStudies() : []
            guard loaded.allSatisfy({ q in q.caseStudy == nil || cases.contains { $0.id == q.caseStudy } }) else {
                throw ContentError.storage("missing case study")
            }
            self.questions = ids.compactMap { byID[$0] }
            self.cases = cases
            self.definition = content.definition
            self.session = ExamSession(snapshot: attempt.snapshot, timerPolicy: self.policy)
            // 再起動時はまず保存した問題へ復元する。見直し経路では続けて openReview を呼ぶ。
            if self.session?.state == .reviewing { try self.session?.handle(.closeReview, at: self.time.now()) }
            self.previousTick = self.time.now()
            self.questionEnteredAt = self.time.now()
        }
    }

    func select(_ choiceID: String) async {
        await run {
            try await self.advanceClock()
            guard var next = self.session, next.state == .inProgress else { return }
            let question = self.questions[next.currentIndex]
            guard question.choices.contains(where: { $0.id == choiceID }) else { return }
            var selected: Set<String> = []
            if case .choices(let ids) = next.answers[question.id] { selected = ids }
            if selected.contains(choiceID) { selected.remove(choiceID) }
            else if question.type == .single { selected = [choiceID] }
            else {
                guard selected.count < question.type.requiredSelections else {
                    self.alert = "session.selectionLimit"; return
                }
                selected.insert(choiceID)
            }
            let selection = AnswerSelection.choices(selected)
            try next.select(selection, for: question.id)
            let now = self.time.now()
            let fact = AnswerFact(examID: self.examID, questionID: question.id, questionRevision: question.revision,
                domain: question.domain, subObjective: question.subObjective, caseStudy: question.caseStudy,
                selection: selection, isCorrect: try self.evaluators.evaluate(selection, for: question), mode: .exam,
                answeredAt: now, elapsedSeconds: max(0, Int(now.timeIntervalSince(self.questionEnteredAt ?? now))))
            // record は解答履歴と snapshot の選択を原子的に保存する。
            try await self.attempts.record(fact, in: self.attemptID)
            self.session = next
            try await self.attempts.save(snapshot: next.snapshot, for: self.attemptID)
            self.questionEnteredAt = now
        }
    }

    func move(to index: Int) async {
        await run {
            try await self.advanceClock()
            guard var next = self.session, next.state == .inProgress else { return }
            try next.move(to: index)
            try await self.attempts.save(snapshot: next.snapshot, for: self.attemptID)
            self.session = next
            self.questionEnteredAt = self.time.now()
        }
    }

    func toggleFlag() async {
        await run {
            try await self.advanceClock()
            guard var next = self.session, next.state == .inProgress else { return }
            try next.toggleFlag(for: next.order.items[next.currentIndex].questionID)
            try await self.attempts.save(snapshot: next.snapshot, for: self.attemptID)
            self.session = next
        }
    }

    func openReview() async {
        await run {
            try await self.advanceClock()
            guard var next = self.session, next.state == .inProgress else { return }
            try next.handle(.openReview, at: self.time.now())
            try await self.attempts.save(snapshot: next.snapshot, for: self.attemptID)
            self.session = next; self.reviewVisible = true
        }
    }

    func closeReview(to index: Int) async {
        await run {
            try await self.advanceClock()
            guard var next = self.session, next.state == .reviewing else { return }
            try next.handle(.closeReview, at: self.time.now())
            try next.move(to: index)
            try await self.attempts.save(snapshot: next.snapshot, for: self.attemptID)
            self.session = next; self.reviewVisible = false
            self.questionEnteredAt = self.time.now()
        }
    }

    func submit() async {
        await run {
            // 確認ダイアログを開いている間の期限超過を手動提出より先に処理する。
            try await self.advanceClock()
            guard var next = self.session, next.state == .reviewing else { return }
            try next.handle(.submit, at: self.time.now())
            self.session = next
        }
    }

    func tick() async { await run(clearAlert: false) {} }

    func scenePhaseChanged(isActive: Bool) async {
        // await 中の lifecycle 更新を捨てず、保存操作の完了後に最新の状態へ追従する。
        wantsActive = isActive
        await run(clearAlert: false) {}
    }

    private func run(errorKey: String = "session.saveFailed", clearAlert: Bool = true,
                     _ operation: () async throws -> Void) async {
        guard !isBusy, !submissionComplete else { return }
        isBusy = true
        if clearAlert { alert = nil }
        defer { isBusy = false }
        do {
            try await operation()
            try await synchronizeLifecycle()
            try await advanceClock()
        } catch {
            alert = errorKey
            Logger(subsystem: "Cloudrill", category: "exam").error("模試の読み込み・保存処理に失敗しました")
            // record/save の失敗中にバックグラウンドへ移った場合にも中断を試みる。
            do { try await synchronizeLifecycle() } catch { }
        }
    }

    private func synchronizeLifecycle() async throws {
        while var next = session {
            let event: ExamSessionEvent
            if wantsActive, next.state == .suspended { event = .resume }
            else if !wantsActive, next.state == .inProgress || next.state == .reviewing { event = .suspend }
            else { return }
            try next.handle(event, at: time.now())
            if case .submitted = next.state { session = next; return }
            if event == .resume, reviewVisible { try next.handle(.openReview, at: time.now()) }
            try await attempts.save(snapshot: next.snapshot, for: attemptID)
            session = next
            questionEnteredAt = time.now()
        }
    }

    private func advanceClock() async throws {
        guard var next = session else { return }
        let now = time.now()
        remainingSeconds = Int(ceil(next.timer?.remaining(at: now).timeInterval ?? 0))
        if let previousTick, let threshold = next.timer?.crossedThreshold(from: previousTick, to: now, policy: policy), remainingSeconds > 0 {
            warning = threshold == .seconds(600) ? .tenMinutes : .fiveMinutes
            feedbackCount += 1
        }
        previousTick = now
        try next.handle(.tick, at: now)
        session = next
        guard case .submitted(let reason) = next.state, let definition else { return }
        try await submission.submit(attemptID: attemptID, definition: definition, questions: questions,
            answers: next.answers, reason: reason, at: now)
        alert = nil
        submissionComplete = true
    }
}
