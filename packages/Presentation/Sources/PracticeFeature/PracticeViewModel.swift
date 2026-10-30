import Foundation
import Observation
import AppCore
import DomainModels
import DomainInterfaces
import StudyModels
import QuestionSelector
import ExamEngine
import ExamFeature

@MainActor @Observable public final class PracticeViewModel {
    public struct State {
        public var phase: Phase = .setup
        public var isBusy = false
        public var alert: String?
        public var selectedIDs: Set<String> = []
        public var index = 0
        public var answers: [AnswerFact] = []
        public var flagged: Set<String> = []
    }
    public enum Phase { case setup, answering, feedback, result }
    public private(set) var state = State()
    public var criteria = PracticeCriteria()
    public private(set) var questions: [Question] = []
    public private(set) var explanation: ExplanationViewModel?
    public let content: any ExamContentProvider
    public static let countOptions: [PracticeCount] = [.fixed(5), .fixed(10), .fixed(20), .all]
    public var domains: [DomainDefinition] { content.definition.domains }
    public var cases: [CaseStudyID] { content.definition.features.caseStudies ? content.definition.caseStudies : [] }
    public var current: Question? { questions.indices.contains(state.index) ? questions[state.index] : nil }
    public var canSubmit: Bool { current.map { state.selectedIDs.count == $0.type.requiredSelections } == true }
    public var summary: AccuracySummary { .init(definition: content.definition, answers: state.answers) }
    public var correctCount: Int { state.answers.filter(\.isCorrect).count }
    private let answers: any AnswerHistoryRepository
    private let cards: any CardStateRepository
    private let time: any TimeSource
    private let router: AppRouter
    private let seedProvider: @Sendable () -> UInt64
    private var presentedAt: Date?
    // A failed save retries the same fact, including its timestamp and elapsed time.
    private var pendingAnswer: AnswerFact?

    public init(content: any ExamContentProvider, preset: PracticePreset? = nil,
                answers: any AnswerHistoryRepository, cards: any CardStateRepository,
                time: any TimeSource, router: AppRouter, seedProvider: @escaping @Sendable () -> UInt64) {
        self.content = content; self.answers = answers; self.cards = cards
        self.time = time; self.router = router; self.seedProvider = seedProvider
        switch preset {
        case .domain(let id): criteria.domains = [id]
        case .caseStudy(let id) where content.definition.features.caseStudies: criteria.caseStudies = [id]
        default: break
        }
    }
    public func start() async {
        guard !state.isBusy, state.phase == .setup else { return }
        state.isBusy = true; state.alert = nil
        defer { state.isBusy = false }
        do {
            let now = time.now()
            let history = try await answers.practiceHistory(examID: content.definition.id, now: now)
            var rng = PracticeRandomGenerator(seed: seedProvider())
            var criteria = criteria
            if !content.definition.features.caseStudies { criteria.caseStudies = [] }
            let ids = QuestionSelector().select(from: content.questionIndex.map(QuestionSummary.init),
                history: history, criteria: criteria, now: now, using: &rng)
            guard !ids.isEmpty else { state.alert = "practice.empty"; return }
            let loaded = try await content.questions(ids: ids)
            guard loaded.count == ids.count, Set(loaded.map(\.id)) == Set(ids) else {
                throw ContentError.unknownQuestionIDs(ids)
            }
            let ordered = ids.compactMap { id in loaded.first { $0.id == id } }
            try await answers.markServed(questionIDs: ids, examID: content.definition.id, at: now)
            questions = ordered; state.flagged = history.flagged
            state.phase = .answering; presentedAt = time.now()
        } catch { state.alert = "practice.loadFailed" }
    }
    public func select(_ id: String) {
        guard !state.isBusy, state.phase == .answering, let current,
              current.choices.contains(where: { $0.id == id }) else { return }
        pendingAnswer = nil; state.alert = nil
        if state.selectedIDs.contains(id) { state.selectedIDs.remove(id) }
        else if current.type.requiredSelections == 1 { state.selectedIDs = [id] }
        else if state.selectedIDs.count < current.type.requiredSelections { state.selectedIDs.insert(id) }
        else { state.alert = "practice.selectionLimit" }
    }
    public func submit() async {
        guard !state.isBusy, state.phase == .answering, canSubmit, let current else { return }
        state.isBusy = true; state.alert = nil
        defer { state.isBusy = false }
        do {
            let selection = AnswerSelection.choices(state.selectedIDs)
            let correct = try AnswerEvaluatorRegistry.standard.evaluate(selection, for: current)
            let now = time.now()
            let fact = pendingAnswer ?? AnswerFact(examID: content.definition.id, questionID: current.id,
                questionRevision: current.revision, domain: current.domain, subObjective: current.subObjective,
                caseStudy: current.caseStudy, selection: selection, isCorrect: correct, mode: .practice,
                answeredAt: now, elapsedSeconds: max(0, Int(now.timeIntervalSince(presentedAt ?? now))))
            pendingAnswer = fact
            try await answers.record(fact)
            state.answers.append(fact); pendingAnswer = nil
            explanation = ExplanationViewModel(content: content, question: current, selectedIDs: state.selectedIDs,
                isCorrect: correct, cards: cards, time: time, router: router)
            state.phase = .feedback
        } catch { state.alert = "practice.saveFailed" }
    }
    public func toggleFlag() async {
        guard !state.isBusy, let current, state.phase != .result else { return }
        state.isBusy = true; state.alert = nil
        defer { state.isBusy = false }
        let flagged = !state.flagged.contains(current.id)
        do {
            try await answers.setFlag(flagged, questionID: current.id, examID: content.definition.id, at: time.now())
            if flagged { state.flagged.insert(current.id) } else { state.flagged.remove(current.id) }
        } catch { state.alert = "practice.saveFailed" }
    }
    public func next() {
        guard !state.isBusy, state.phase == .feedback else { return }
        explanation = nil; state.selectedIDs = []; state.alert = nil
        if state.index + 1 == questions.count { state.phase = .result }
        else { state.index += 1; state.phase = .answering; presentedAt = time.now() }
    }
}

private struct PracticeRandomGenerator: RandomNumberGenerator {
    var seed: UInt64
    mutating func next() -> UInt64 {
        seed &+= 0x9E3779B97F4A7C15
        var value = seed
        value = (value ^ (value >> 30)) &* 0xBF58476D1CE4E5B9
        value = (value ^ (value >> 27)) &* 0x94D049BB133111EB
        return value ^ (value >> 31)
    }
}
