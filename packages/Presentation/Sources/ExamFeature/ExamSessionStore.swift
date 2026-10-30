import Foundation
import AppCore
import DomainModels

/// 同じ受験の解答・見直し経路で、読み込んだ問題と保存処理を共有する。
@MainActor public final class ExamSessionStore {
    private let examID: ExamID
    private let dependencies: AppDependencies
    private let router: AppRouter
    private var cached: (id: UUID, model: ExamSessionViewModel)?
    public init(examID: ExamID, dependencies: AppDependencies, router: AppRouter) {
        self.examID = examID; self.dependencies = dependencies; self.router = router
    }
    public func model(for attemptID: UUID) -> ExamSessionViewModel {
        if let cached, cached.id == attemptID { return cached.model }
        let model = ExamSessionViewModel(examID: examID, attemptID: attemptID, contentResolver: dependencies.contentResolver,
            attempts: dependencies.attempts, pins: dependencies.pins, cards: dependencies.cards, settings: dependencies.settings,
            time: dependencies.time, evaluators: dependencies.evaluators, router: router)
        cached = (attemptID, model)
        return model
    }
}
