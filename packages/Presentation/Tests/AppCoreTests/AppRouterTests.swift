import Foundation
import Testing
@testable import AppCore

@MainActor struct AppRouterTests {
    @Test func openSwitchesTabAndKeepsIndependentPaths() {
        let router = AppRouter()
        router.open(.practiceSetup(.domain(4)))
        router.open(.examStart(examSet: 1))
        router.open(.deck("all"))
        #expect(router.selectedTab == .cards)
        #expect(router.path(for: .exam) == [.practiceSetup(.domain(4)), .examStart(examSet: 1)])
        #expect(router.path(for: .cards) == [.deck("all")])
    }

    @Test func submitReplacesStackAndSwitchResetsAllTabs() {
        let router = AppRouter(), id = UUID()
        router.open(.examSession(attemptID: id))
        router.open(.examReview(attemptID: id))
        router.showExamResult(attemptID: id)
        #expect(router.path(for: .exam) == [.examResult(attemptID: id)])
        router.reset()
        #expect(router.selectedTab == .home)
        #expect(Tab.allCases.allSatisfy { router.path(for: $0).isEmpty })
    }

    @Test func everyRouteHasATabAndNavigationPopIsWritable() {
        let id = UUID()
        let cases: [(Route, Tab)] = [
            (.examStart(examSet: 1), .exam), (.examSession(attemptID: id), .exam),
            (.examReview(attemptID: id), .exam), (.examResult(attemptID: id), .exam),
            (.explanation(attemptID: nil, questionID: "Q1"), .exam), (.practiceSetup(nil), .exam),
            (.practiceSession(id), .exam), (.practiceResult(id), .exam),
            (.deck("all"), .cards), (.cardSession("all"), .cards),
            (.docsIndex(domain: nil), .learn), (.doc(subObjective: "NET.1"), .learn),
            (.caseList, .learn), (.caseDetail("case-a"), .learn), (.analyticsDomain(4), .analytics),
        ]
        for (route, tab) in cases { #expect(route.tab == tab) }
        let router = AppRouter()
        router.open(.caseList)
        router.setPath([], for: .learn)
        #expect(router.path(for: .learn).isEmpty)
    }
}
