import Foundation
import Observation
import AppCore
import DomainModels
import DomainInterfaces

/// ケーススタディの一覧(SCR-043)。試験定義の `caseStudies` の順に並べる(FR-CASE-01)
@MainActor @Observable public final class CaseListViewModel {
    public enum Phase: Equatable { case idle, loaded([CaseStudy]), failed }
    public private(set) var phase: Phase = .idle
    public private(set) var isLoading = false
    public var isAvailable: Bool { content.definition.features.caseStudies }
    private let content: any ExamContentProvider
    private let router: AppRouter

    public init(content: any ExamContentProvider, router: AppRouter) {
        self.content = content; self.router = router
    }

    public func load() async {
        guard isAvailable, !isLoading else { return }
        if case .loaded = phase { return }
        isLoading = true
        defer { isLoading = false }
        do {
            phase = .loaded(Self.ordered(try await content.caseStudies(), by: content.definition.caseStudies))
        } catch { phase = .failed }
    }

    public func open(_ id: CaseStudyID) { router.open(.caseDetail(id)) }

    /// 定義にないケースは出さない(索引と定義の整合は起動時に確認済み)
    static func ordered(_ cases: [CaseStudy], by order: [CaseStudyID]) -> [CaseStudy] {
        order.compactMap { id in cases.first { $0.id == id } }
    }
}
