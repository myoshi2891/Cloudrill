import Foundation
import Observation
import AppCore
import DomainModels
import DomainInterfaces
import StudyModels

public struct HomeState: Equatable, Sendable {
    public var dueCards = 0
    public var weakDomain: Int?
    public var resumeAttemptID: UUID?
    public var isLoading = false
    public var isLoaded = false
    public var alert: AppAlert?
}

@MainActor @Observable public final class HomeViewModel {
    public private(set) var state = HomeState()
    public let definition: ExamDefinition
    public let router: AppRouter
    public var title: String { definition.shortName }
    private let answers: any AnswerHistoryRepository
    private let cards: any CardStateRepository
    private let attempts: any ExamAttemptRepository
    private let time: any TimeSource

    public init(definition: ExamDefinition, answers: any AnswerHistoryRepository,
                cards: any CardStateRepository, attempts: any ExamAttemptRepository,
                time: any TimeSource, router: AppRouter) {
        self.definition = definition; self.answers = answers; self.cards = cards
        self.attempts = attempts; self.time = time; self.router = router
    }

    public func refresh() async {
        guard !state.isLoading else { return }
        state.isLoading = true
        defer { state.isLoading = false }
        do {
            let facts = try await answers.answers(examID: definition.id)
            let scheduled = definition.features.flashcards ? try await cards.scheduledCards(examID: definition.id) : []
            let attempt = try await attempts.inProgress(examID: definition.id)
            guard !Task.isCancelled else { return }
            let now = time.now()
            state = HomeState(dueCards: scheduled.filter { $0.card.phase != .new && $0.card.due <= now }.count,
                              weakDomain: AccuracySummary(definition: definition, answers: facts).weakestDomain,
                              resumeAttemptID: attempt?.id, isLoaded: true)
        } catch {
            guard !Task.isCancelled else { return }
            state.alert = .persistenceFailed
        }
    }

    public func startLearning() { router.open(.practiceSetup(nil)) }
    public func practiceWeakDomain() {
        guard let domain = state.weakDomain else { return }
        router.open(.practiceSetup(.domain(domain)))
    }
    public func reviewCards() { router.setPath([], for: .cards); router.selectedTab = .cards }
    public func resumeExam() {
        guard let id = state.resumeAttemptID else { return }
        router.open(.examSession(attemptID: id))
    }
}
