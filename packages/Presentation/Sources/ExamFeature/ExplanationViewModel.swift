import Foundation
import Observation
import AppCore
import DomainModels
import DomainInterfaces
import StudyModels
import ExamEngine

/// S15 の報告フォームへ渡す、表示中のコンテンツを特定する値。
public struct QuestionReportContext: Identifiable, Equatable, Sendable {
    public let examID: ExamID
    public let questionID: String
    public let questionRevision: Int
    public let packVersion: String
    public var id: String { "\(examID)/\(packVersion)/\(questionID)/\(questionRevision)" }
}

@MainActor @Observable public final class ExplanationViewModel {
    public private(set) var question: Question?
    public private(set) var choices: [Choice] = []
    public private(set) var selectedIDs: Set<String> = []
    public private(set) var isCorrect = false
    public private(set) var isUnanswered = true
    public private(set) var canAddToCards = false
    public private(set) var isAddedToCards = false
    public private(set) var relatedDoc: String?
    public private(set) var report: QuestionReportContext?
    public private(set) var isLoading = false
    public private(set) var isAdding = false
    public private(set) var error: String?
    public private(set) var actionError: String?
    public var preferEnglish = false
    private var reportContext: QuestionReportContext?
    private let examID: ExamID
    private let attemptID: UUID
    private let questionID: String
    private let resolver: any ExamContentResolving
    private let attempts: any ExamAttemptRepository
    private let cards: any CardStateRepository
    private let time: any TimeSource
    private let router: AppRouter

    public init(examID: ExamID, attemptID: UUID, questionID: String, resolver: any ExamContentResolving,
                attempts: any ExamAttemptRepository, cards: any CardStateRepository,
                time: any TimeSource, router: AppRouter) {
        self.examID = examID; self.attemptID = attemptID; self.questionID = questionID
        self.resolver = resolver; self.attempts = attempts; self.cards = cards; self.time = time; self.router = router
    }
    public func load() async {
        guard !isLoading, !isAdding else { return }
        isLoading = true; error = nil
        defer { isLoading = false }
        do {
            if question == nil {
                let loaded = try await SubmittedExamContent.load(examID: examID, attemptID: attemptID, attempts: attempts, resolver: resolver)
                guard let question = loaded.questions.first(where: { $0.id == questionID }),
                      let order = loaded.summary.attempt.snapshot.order.items.first(where: { $0.questionID == questionID }) else {
                    throw ContentError.unknownQuestionIDs([questionID])
                }
                let answer = loaded.summary.attempt.snapshot.answers[questionID]
                let correct = try answer.map { try AnswerEvaluatorRegistry.standard.evaluate($0, for: question) } ?? false
                choices = order.choiceIDs.compactMap { id in question.choices.first { $0.id == id } }
                if case .choices(let ids) = answer { selectedIDs = ids }
                isCorrect = correct; isUnanswered = answer == nil
                canAddToCards = loaded.content.definition.features.flashcards
                relatedDoc = loaded.content.definition.features.docs && loaded.content.docsIndex.contains {
                    $0.subObjective == question.subObjective
                } ? question.subObjective : nil
                reportContext = QuestionReportContext(examID: examID, questionID: questionID,
                    questionRevision: question.revision, packVersion: loaded.content.packVersion)
                self.question = question
            }
        } catch { self.error = "explanation.loadFailed"; return }
        // カードの取得失敗で解説本文を隠さない。取得・追加ともに同じ操作エラーとして再試行できる。
        if canAddToCards {
            do {
                isAddedToCards = try await cards.card(id: "Q:" + questionID, examID: examID) != nil
                actionError = nil
            } catch { actionError = "explanation.cardLoadFailed" }
        }
    }
    public func addToCards() async {
        guard question != nil, canAddToCards, !isLoading, !isAdding, !isAddedToCards else { return }
        isAdding = true; actionError = nil
        defer { isAdding = false }
        do {
            try await cards.addCardFromQuestion(questionID: questionID, examID: examID, at: time.now())
            isAddedToCards = true
        } catch { actionError = "session.saveFailed" }
    }
    public func openReport() { report = reportContext }
    public func closeReport() { report = nil }
    public func openRelatedDoc() {
        guard let relatedDoc else { return }
        router.open(.doc(subObjective: relatedDoc))
    }
}
