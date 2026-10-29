import Foundation
import Observation
import AppCore
import DomainModels
import DomainInterfaces
import StudyModels

/// 各区画は独立して読み込む。失敗した区画は前回の値を保ち、他の区画の操作は隠さない。
public struct HomeState: Equatable, Sendable {
    public var dueCards = 0
    public var weakDomain: Int?
    public var resumeAttemptID: UUID?
    public var isLoading = false
    public var isLoaded = false
    public var isHistoryLoaded = false
    public var isCardsLoaded = false
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
    private var rerunRequested = false

    public init(definition: ExamDefinition, answers: any AnswerHistoryRepository,
                cards: any CardStateRepository, attempts: any ExamAttemptRepository,
                time: any TimeSource, router: AppRouter) {
        self.definition = definition; self.answers = answers; self.cards = cards
        self.attempts = attempts; self.time = time; self.router = router
    }

    /// 読み込み中の呼び出しは捨てずに、完了後にもう一度読み直す。
    /// 呼び出し元の Task が取り消されても、読めた結果は反映する(空画面のまま残さない)。
    public func refresh() async {
        guard !state.isLoading else { rerunRequested = true; return }
        state.isLoading = true
        defer { state.isLoading = false }
        repeat {
            rerunRequested = false
            await load()
        } while rerunRequested
    }

    private func load() async {
        var failed = false
        let examID = definition.id
        do {
            let outcomes = try await answers.outcomes(examID: examID)
            state.weakDomain = AccuracySummary(definition: definition, outcomes: outcomes).weakestDomain
            state.isHistoryLoaded = true
        } catch { failed = true }
        if definition.features.flashcards {
            do {
                let scheduled = try await cards.scheduledCards(examID: examID)
                let now = time.now()
                state.dueCards = scheduled.filter { $0.card.phase != .new && $0.card.due <= now }.count
                state.isCardsLoaded = true
            } catch { failed = true }
        }
        do {
            state.resumeAttemptID = try await attempts.inProgress(examID: examID)?.id
        } catch { failed = true }
        state.alert = failed ? .persistenceFailed : nil
        state.isLoaded = true
    }

    public func startLearning() { openExam(.practiceSetup(nil)) }
    public func practiceWeakDomain() {
        guard let domain = state.weakDomain else { return }
        openExam(.practiceSetup(.domain(domain)))
    }
    public func reviewCards() { router.setPath([], for: .cards); router.selectedTab = .cards }
    public func resumeExam() {
        guard let id = state.resumeAttemptID else { return }
        openExam(.examSession(attemptID: id))
    }

    /// ホームからの入口は試験タブの経路を置き換える(前回の画面の上に積まない)。
    private func openExam(_ route: Route) {
        router.setPath([route], for: route.tab)
        router.selectedTab = route.tab
    }
}
