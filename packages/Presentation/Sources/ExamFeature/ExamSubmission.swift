import Foundation
import DomainModels
import DomainInterfaces
import StudyModels
import ExamEngine

/// 手動・時間切れ共通の提出処理。呼び出し元の Controller が操作を直列化する。
@MainActor final class ExamSubmission {
    private let attempts: any ExamAttemptRepository
    private let pins: any PackPinning
    private let cards: any CardStateRepository
    private let settings: any SettingsRepository
    private let evaluators: AnswerEvaluatorRegistry
    private var plan: Plan?
    private var finalized = false
    private var addedCards: Set<String> = []
    private struct Plan {
        let result: ExamResult
        let mistakeIDs: [String]
        let date: Date
    }

    init(attempts: any ExamAttemptRepository, pins: any PackPinning, cards: any CardStateRepository,
         settings: any SettingsRepository, evaluators: AnswerEvaluatorRegistry) {
        self.attempts = attempts; self.pins = pins; self.cards = cards
        self.settings = settings; self.evaluators = evaluators
    }

    func submit(attemptID: UUID, definition: ExamDefinition, questions: [Question],
                answers: [String: AnswerSelection], reason: SubmitReason, at date: Date) async throws {
        if plan == nil {
            let result = try ScoringPolicies.policy(for: definition.scoring.policy).score(
                ScoringInput(definition: definition, questions: questions, answers: answers), evaluators: evaluators)
            var mistakeIDs: [String] = []
            if definition.features.flashcards, try await settings.preference(examID: definition.id).autoCardFromMistakes {
                // 未解答は採点上は不正解だが、解答して間違えた問題だけを復習カードにする。
                for question in questions {
                    if let answer = answers[question.id], try !evaluators.evaluate(answer, for: question) {
                        mistakeIDs.append(question.id)
                    }
                }
            }
            plan = Plan(result: result, mistakeIDs: mistakeIDs, date: date)
        }
        guard let plan else { return }
        if !finalized {
            try await attempts.finalize(attemptID: attemptID, result: plan.result, reason: reason, at: plan.date)
            finalized = true
        }
        for id in plan.mistakeIDs where !addedCards.contains(id) {
            try await cards.addCardFromQuestion(questionID: id, examID: definition.id, at: plan.date)
            addedCards.insert(id)
        }
        try await pins.unpin(attemptID: attemptID, for: definition.id)
    }
}
