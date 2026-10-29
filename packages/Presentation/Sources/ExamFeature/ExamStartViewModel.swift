import Foundation
import Observation
import AppCore
import DomainModels
import DomainInterfaces
import StudyModels
import ExamEngine

@MainActor @Observable public final class ExamStartViewModel {
    public private(set) var cases: [CaseStudy] = []
    public private(set) var inProgress: AttemptSnapshot?
    public private(set) var isBusy = false
    public private(set) var error: String?
    public private(set) var isLoaded = false
    public let examSet: Int
    public var questionCount: Int { content.definition.format.mockExam.questionCount }
    public var durationMinutes: Int { content.definition.format.durationMinutes }
    private let content: any ExamContentProvider
    private let attempts: any ExamAttemptRepository
    private let pins: any PackPinning
    private let settings: any SettingsRepository
    private let time: any TimeSource
    private let seedProvider: @Sendable () -> UInt64
    private let router: AppRouter
    // abandon 成功後に unpin が失敗したら、破棄を重ねずに解除だけを再試行する。
    private var pendingUnpin: UUID?

    public init(content: any ExamContentProvider, examSet: Int, attempts: any ExamAttemptRepository,
                pins: any PackPinning, settings: any SettingsRepository, time: any TimeSource,
                seedProvider: @escaping @Sendable () -> UInt64, router: AppRouter) {
        self.content = content; self.examSet = examSet; self.attempts = attempts; self.pins = pins
        self.settings = settings; self.time = time; self.seedProvider = seedProvider; self.router = router
    }

    private func selectedSet() throws -> ExamSet {
        guard let set = ExamTopViewModel(content: content).sets.first(where: { $0.id == examSet }) else {
            throw ContentError.fileMissing("exam set")
        }
        return set
    }
    public func load() async {
        guard !isBusy else { return }
        isBusy = true; error = nil
        defer { isBusy = false }
        do {
            let set = try selectedSet()
            if content.definition.features.caseStudies {
                let available = try await content.caseStudies()
                cases = try set.caseStudies.map { id in
                    guard let item = available.first(where: { $0.id == id }) else { throw ContentError.fileMissing(id.rawValue) }
                    return item
                }
            }
            if pendingUnpin == nil { inProgress = try await attempts.inProgress(examID: content.definition.id) }
            isLoaded = true
        } catch { self.error = "exam.loadFailed" }
    }
    public func start() async {
        guard !isBusy, pendingUnpin == nil else { return }
        isBusy = true; error = nil
        defer { isBusy = false }
        do {
            inProgress = try await attempts.inProgress(examID: content.definition.id)
            guard inProgress == nil else { return }
            let set = try selectedSet()
            let user = try await settings.settings()
            let questions = try await content.questions(ids: set.questionIDs)
            var rng = ExamRandomGenerator(seed: seedProvider())
            let order = try ExamOrderBuilder.make(questionIDs: set.questionIDs,
                questions: Dictionary(questions.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first }),
                shuffleChoices: user.shuffleChoices, using: &rng)
            var session = ExamSession(order: order, duration: .seconds(durationMinutes * 60), timerPolicy: .init())
            let now = time.now()
            try session.handle(.start, at: now)
            let id = try await attempts.start(examID: content.definition.id, examSet: examSet,
                packVersion: content.packVersion, snapshot: session.snapshot)
            let attempt = AttemptSnapshot(id: id, examID: content.definition.id, examSet: examSet,
                packVersion: content.packVersion, startedAt: now, snapshot: session.snapshot)
            // pin 失敗でも保存した受験を再開/破棄できる。
            inProgress = attempt
            try await open(attempt)
        } catch { self.error = "exam.startFailed" }
    }
    public func resume() async {
        guard !isBusy, pendingUnpin == nil else { return }
        isBusy = true; error = nil
        defer { isBusy = false }
        do {
            inProgress = try await attempts.inProgress(examID: content.definition.id)
            if let inProgress { try await open(inProgress) }
        } catch { self.error = "exam.startFailed" }
    }
    private func open(_ attempt: AttemptSnapshot) async throws {
        try await pins.pin(attempt.packVersion, for: attempt.examID, attemptID: attempt.id)
        router.setPath([.examSession(attemptID: attempt.id)], for: .exam)
        router.selectedTab = .exam
    }
    public func abandon() async {
        guard !isBusy else { return }
        isBusy = true; error = nil
        defer { isBusy = false }
        do {
            if pendingUnpin == nil {
                inProgress = try await attempts.inProgress(examID: content.definition.id)
                guard let inProgress else { return }
                try await attempts.abandon(attemptID: inProgress.id)
                pendingUnpin = inProgress.id
            }
            if let pendingUnpin { try await pins.unpin(attemptID: pendingUnpin, for: content.definition.id) }
            pendingUnpin = nil; inProgress = nil
        } catch { self.error = "exam.abandonFailed" }
    }
}

/// SplitMix64。保存するのは seed ではなく ExamOrderBuilder が決定した出題順。
private struct ExamRandomGenerator: RandomNumberGenerator {
    var seed: UInt64
    mutating func next() -> UInt64 {
        seed &+= 0x9E37_79B9_7F4A_7C15
        var z = seed
        z = (z ^ (z >> 30)) &* 0xBF58_476D_1CE4_E5B9
        z = (z ^ (z >> 27)) &* 0x94D0_49BB_1331_11EB
        return z ^ (z >> 31)
    }
}
