import Foundation
import Observation
import AppCore
import DomainModels
import DomainInterfaces

/// ケーススタディの詳細(SCR-044)。要約・要件・既存環境と公式ページへのリンクを出す(LG-03)
@MainActor @Observable public final class CaseDetailViewModel {
    public enum Phase: Equatable { case idle, loaded(CaseStudy), notFound, failed }
    public private(set) var phase: Phase = .idle
    public private(set) var isLoading = false
    public let id: CaseStudyID
    private let content: any ExamContentProvider
    private let router: AppRouter

    public init(content: any ExamContentProvider, id: CaseStudyID, router: AppRouter) {
        self.content = content; self.id = id; self.router = router
    }

    public func load() async {
        guard !isLoading else { return }
        if case .loaded = phase { return }
        guard content.definition.features.caseStudies, content.definition.caseStudies.contains(id) else {
            phase = .notFound; return
        }
        isLoading = true
        defer { isLoading = false }
        do {
            guard let found = try await content.caseStudies().first(where: { $0.id == id }) else { phase = .notFound; return }
            phase = .loaded(found)
        } catch { phase = .failed }
    }

    /// 「このケースの問題を解く」。練習の条件設定(試験タブ)をこのケースで開く
    public func practice() {
        guard case .loaded = phase else { return }
        router.open(.practiceSetup(.caseStudy(id)))
    }
}
