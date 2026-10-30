import Foundation
import Observation
import DomainModels

public enum Tab: String, CaseIterable, Hashable, Sendable { case home, exam, cards, learn, analytics }
public enum PracticePreset: Hashable, Sendable { case domain(Int); case caseStudy(CaseStudyID) }
public struct DeckID: StringIdentifier {
    public let rawValue: String
    public init(rawValue: String) { self.rawValue = rawValue }
}
public enum Route: Hashable, Sendable {
    case examStart(examSet: Int)
    case examSession(attemptID: UUID)
    case examReview(attemptID: UUID)
    case examResult(attemptID: UUID)
    case explanation(attemptID: UUID?, questionID: String)
    case practiceSetup(PracticePreset?)
    case practiceSession(UUID)
    case practiceResult(UUID)
    case deck(DeckID)
    case cardSession(DeckID)
    case docsIndex(domain: Int?)
    case doc(subObjective: String)
    case caseList
    case caseDetail(CaseStudyID)
    case analyticsDomain(Int)

    public var tab: Tab {
        switch self {
        case .examStart, .examSession, .examReview, .examResult, .explanation,
             .practiceSetup, .practiceSession, .practiceResult: .exam
        case .deck, .cardSession: .cards
        case .docsIndex, .doc, .caseList, .caseDetail: .learn
        case .analyticsDomain: .analytics
        }
    }
}

@MainActor @Observable public final class AppRouter {
    public var selectedTab: Tab = .home
    private var paths: [Tab: [Route]] = [:]
    public init() {}
    public func path(for tab: Tab) -> [Route] { paths[tab, default: []] }
    public func setPath(_ path: [Route], for tab: Tab) { paths[tab] = path }
    public func open(_ route: Route) {
        selectedTab = route.tab
        paths[route.tab, default: []].append(route)
    }
    public func showExamResult(attemptID: UUID) {
        selectedTab = .exam
        paths[.exam] = [.examResult(attemptID: attemptID)]
    }
    public func reset() { paths = [:]; selectedTab = .home }
}
