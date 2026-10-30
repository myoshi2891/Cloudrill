import Foundation
import Observation
import AppCore
import DomainModels
import DomainInterfaces
import StudyModels
import ExamEngine

public struct ResultBreakdown: Identifiable, Sendable {
    public let id: String
    public let name: String
    public let tally: ScoreTally
}
public struct ResultQuestion: Identifiable, Sendable {
    public let id: String
    public let number: Int
    public let stem: String
    public let isCorrect: Bool
    public let isUnanswered: Bool
}

@MainActor @Observable public final class ExamResultViewModel {
    public private(set) var summary: AttemptSummary?
    public private(set) var result: ExamResult?
    public private(set) var domains: [ResultBreakdown] = []
    public private(set) var cases: [ResultBreakdown] = []
    public private(set) var questions: [ResultQuestion] = []
    public private(set) var elapsedMinutes = 0
    public private(set) var isLoading = false
    public private(set) var error: String?
    private let examID: ExamID
    private let attemptID: UUID
    private let resolver: any ExamContentResolving
    private let attempts: any ExamAttemptRepository
    private let router: AppRouter

    public init(examID: ExamID, attemptID: UUID, resolver: any ExamContentResolving,
                attempts: any ExamAttemptRepository, router: AppRouter) {
        self.examID = examID; self.attemptID = attemptID; self.resolver = resolver
        self.attempts = attempts; self.router = router
    }
    public var scoreText: String { result.map { Self.scoreText($0.total) } ?? "" }
    public static func scoreText(_ tally: ScoreTally) -> String {
        guard let ratio = tally.ratio else { return String(localized: "result.noQuestions", bundle: .module) }
        return String(format: String(localized: "result.score", bundle: .module), tally.correct, tally.total, Int((ratio * 100).rounded()))
    }
    public func load() async {
        guard !isLoading, result == nil else { return }
        isLoading = true; error = nil
        defer { isLoading = false }
        do {
            let loaded = try await SubmittedExamContent.load(examID: examID, attemptID: attemptID, attempts: attempts, resolver: resolver)
            let definition = loaded.content.definition
            let snapshot = loaded.summary.attempt.snapshot
            let scored = try ScoringPolicies.policy(for: definition.scoring.policy).score(
                .init(definition: definition, questions: loaded.questions, answers: snapshot.answers), evaluators: .standard)
            guard scored.total == loaded.summary.total, let timer = snapshot.timer else {
                throw PersistenceError.corrupted("submitted result mismatch")
            }
            let caseStudies = definition.features.caseStudies ? try await loaded.content.caseStudies() : []
            guard scored.byCaseStudy.keys.allSatisfy({ id in caseStudies.contains { $0.id == id } }) else {
                throw ContentError.storage("missing result case study")
            }
            let rows = try loaded.questions.enumerated().map { index, question in
                let answer = snapshot.answers[question.id]
                return ResultQuestion(id: question.id, number: index + 1, stem: question.stem.ja,
                    isCorrect: try answer.map { try AnswerEvaluatorRegistry.standard.evaluate($0, for: question) } ?? false,
                    isUnanswered: answer == nil)
            }
            domains = definition.domains.map {
                ResultBreakdown(id: String($0.id), name: $0.name.ja, tally: scored.byDomain[$0.id] ?? .init(correct: 0, total: 0))
            }
            cases = caseStudies.compactMap { item in
                scored.byCaseStudy[item.id].map { ResultBreakdown(id: item.id.rawValue, name: item.name.ja, tally: $0) }
            }
            elapsedMinutes = Int(max(0, timer.duration.timeInterval - timer.remaining(at: loaded.summary.submittedAt).timeInterval)) / 60
            questions = rows; summary = loaded.summary; result = scored
        } catch { self.error = "result.loadFailed" }
    }
    public func openExplanation(questionID: String) {
        guard questions.contains(where: { $0.id == questionID }) else { return }
        router.open(.explanation(attemptID: attemptID, questionID: questionID))
    }
}
