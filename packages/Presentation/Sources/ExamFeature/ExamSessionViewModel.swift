import Foundation
import Observation
import AppCore
import DomainModels
import DomainInterfaces
import StudyModels
import ExamEngine

/// 解答用の値には正解・解説を含めない。
public struct ChoiceQuestionPresentation: Equatable, Sendable {
    public struct Option: Equatable, Sendable, Identifiable {
        public let id: String
        public let text: String
    }
    public let id: String
    public let stem: String
    public let requiredSelections: Int
    public let choices: [Option]

    init(question: Question, choiceIDs: [String]) {
        id = question.id; stem = question.stem.ja; requiredSelections = question.type.requiredSelections
        choices = choiceIDs.compactMap { id in
            question.choices.first(where: { $0.id == id }).map { Option(id: $0.id, text: $0.text.ja) }
        }
    }
}

public enum ExamSessionWarning: Sendable { case tenMinutes, fiveMinutes }
public struct ExamSessionViewState: Sendable {
    public var question: ChoiceQuestionPresentation?
    public var selected: Set<String> = []
    public var caseStudy: CaseStudy?
    public var currentIndex = 0
    public var totalCount = 0
    public var isFlagged = false
    public var remainingSeconds = 0
    public var warning: ExamSessionWarning?
    public var feedbackCount = 0
    public var sessionState: ExamSessionState?
    public var isBusy = false
    public var alert: String?
}

@MainActor @Observable public final class ExamSessionViewModel {
    let controller: ExamSessionController
    private let router: AppRouter
    private let attemptID: UUID
    private var didNavigate = false

    public init(examID: ExamID, attemptID: UUID, contentResolver: any ExamContentResolving,
                attempts: any ExamAttemptRepository, pins: any PackPinning, cards: any CardStateRepository,
                settings: any SettingsRepository, time: any TimeSource,
                evaluators: AnswerEvaluatorRegistry = .standard, router: AppRouter) {
        controller = ExamSessionController(examID: examID, attemptID: attemptID, resolver: contentResolver,
            attempts: attempts, pins: pins, cards: cards, settings: settings, time: time, evaluators: evaluators)
        self.router = router; self.attemptID = attemptID
    }

    public var state: ExamSessionViewState {
        var value = ExamSessionViewState()
        value.isBusy = controller.isBusy; value.alert = controller.alert
        value.remainingSeconds = controller.remainingSeconds; value.warning = controller.warning
        value.feedbackCount = controller.feedbackCount
        guard let session = controller.session else { return value }
        value.sessionState = session.state
        value.currentIndex = session.currentIndex; value.totalCount = session.order.items.count
        let question = controller.questions[session.currentIndex]
        value.question = ChoiceQuestionPresentation(question: question, choiceIDs: session.order.items[session.currentIndex].choiceIDs)
        if case .choices(let ids) = session.answers[question.id] { value.selected = ids }
        value.isFlagged = session.flags.contains(question.id)
        value.caseStudy = controller.cases.first { $0.id == question.caseStudy }
        return value
    }

    public func load() async { await controller.load(); navigateIfSubmitted() }
    public func select(choiceID: String) async { await controller.select(choiceID); navigateIfSubmitted() }
    public func move(to index: Int) async { await controller.move(to: index); navigateIfSubmitted() }
    public func toggleFlag() async { await controller.toggleFlag(); navigateIfSubmitted() }
    public func tick() async { await controller.tick(); navigateIfSubmitted() }
    public func scenePhaseChanged(isActive: Bool) async {
        await controller.scenePhaseChanged(isActive: isActive); navigateIfSubmitted()
    }
    public func openReview() async {
        await controller.openReview()
        navigateIfSubmitted()
        if controller.session?.state == .reviewing {
            router.setPath([.examSession(attemptID: attemptID), .examReview(attemptID: attemptID)], for: .exam)
            router.selectedTab = .exam
        }
    }
    func returnToQuestion(index: Int) async {
        await controller.closeReview(to: index)
        navigateIfSubmitted()
        if controller.session?.state == .inProgress {
            router.setPath([.examSession(attemptID: attemptID)], for: .exam)
            router.selectedTab = .exam
        }
    }
    func confirmSubmit() async { await controller.submit(); navigateIfSubmitted() }

    public func showQuestions() async {
        await load()
        await scenePhaseChanged(isActive: true)
        if let session = controller.session, session.state == .reviewing {
            await returnToQuestion(index: session.currentIndex)
        }
    }
    public func viewDisappeared() async {
        // 解答↔見直しの画面遷移ではタイマーを中断しない。
        let activeRoutes: [Route] = [.examSession(attemptID: attemptID), .examReview(attemptID: attemptID)]
        if router.selectedTab == .exam, let route = router.path(for: .exam).last, activeRoutes.contains(route) { return }
        await scenePhaseChanged(isActive: false)
    }
    private func navigateIfSubmitted() {
        guard controller.submissionComplete, !didNavigate else { return }
        didNavigate = true
        router.showExamResult(attemptID: attemptID)
    }
}
