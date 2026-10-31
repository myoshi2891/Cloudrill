import Foundation
import Testing
import AnalyticsFeature
import AppCore
import DomainModels
import DomainInterfaces
import StudyModels
import QuestionSelector

@MainActor struct AnalyticsViewModelTests {
    @Test func accuracyByDomain() async throws {
        // Arrange: ドメイン 1 で 10 問中 7 問正解
        let answers = AnalyticsAnswers(["test-alpha": outcomes("1.1", correct: 7, wrong: 3)])
        let model = AnalyticsViewModel(definition: try definition("test-alpha"), answers: answers)
        // Act
        await model.refresh()
        // Assert
        let domain = try #require(model.state.sections.first { $0.id == 1 }).domain
        #expect(domain.tally == ScoreTally(correct: 7, total: 10))
        #expect(domain.accuracyText == "70%")
        #expect(model.state.isLoaded)
        #expect(!model.state.isEmpty)
    }

    @Test func accuracyBySubObjective() async throws {
        // 定義と逆の順に解答しても、定義の順で、解答のあるサブ項目だけを出す
        let answers = AnalyticsAnswers(["test-alpha": outcomes("1.3", correct: 1, wrong: 2) + outcomes("1.1", correct: 2, wrong: 0)])
        let model = AnalyticsViewModel(definition: try definition("test-alpha"), answers: answers)
        await model.refresh()
        let section = try #require(model.state.sections.first { $0.id == 1 })
        #expect(section.subObjectives.map(\.id) == ["1.1", "1.3"])
        #expect(section.subObjectives.map(\.accuracyText) == ["100%", "33%"])
        #expect(model.state.sections.first { $0.id == 2 }?.subObjectives.isEmpty == true)
    }

    @Test func noAnswersDomain() async throws {
        // ドメイン 1 は全問不正解(0%)、ドメイン 2 は解答なし(—)
        let answers = AnalyticsAnswers(["test-alpha": outcomes("1.1", correct: 0, wrong: 2)])
        let model = AnalyticsViewModel(definition: try definition("test-alpha"), answers: answers)
        await model.refresh()
        #expect(model.state.sections.first { $0.id == 1 }?.domain.accuracyText == "0%")
        #expect(model.state.sections.first { $0.id == 2 }?.domain.accuracyText == "—")
    }

    @Test func emptyHistoryShowsAllDomainsAsDash() async throws {
        let model = AnalyticsViewModel(definition: try definition("test-alpha"), answers: AnalyticsAnswers([:]))
        await model.refresh()
        #expect(model.state.isEmpty)
        #expect(model.state.sections.map(\.domain.accuracyText) == Array(repeating: "—", count: 6))
    }

    @Test func domainNamesFromDefinition() async throws {
        let beta = try definition("test-beta")
        let model = AnalyticsViewModel(definition: beta, answers: AnalyticsAnswers([:]))
        await model.refresh()
        #expect(model.state.sections.count == 4)
        #expect(model.state.sections.map(\.domain.name) == beta.domains.map(\.name))
        #expect(model.state.sections.map(\.domainIndex) == [0, 1, 2, 3])
    }

    @Test func perExamOnly() async throws {
        // 2 試験に解答がある。選択中の試験(beta)だけを集計する
        let answers = AnalyticsAnswers([
            "test-alpha": outcomes("1.1", correct: 5, wrong: 0),
            "test-beta": outcomes("NET.1", correct: 1, wrong: 1),
        ])
        let model = AnalyticsViewModel(definition: try definition("test-beta"), answers: answers)
        await model.refresh()
        #expect(await answers.requested == ["test-beta"])
        #expect(model.state.sections.map(\.domain.tally.total) == [0, 2, 0, 0])
        #expect(model.state.sections[1].subObjectives.map(\.accuracyText) == ["50%"])
    }

    @Test func loadFailureKeepsPreviousAndCanRetry() async throws {
        let answers = AnalyticsAnswers(["test-alpha": outcomes("1.1", correct: 1, wrong: 0)])
        let model = AnalyticsViewModel(definition: try definition("test-alpha"), answers: answers)
        await answers.setFailing(true)
        await model.refresh()
        #expect(model.state.loadFailed)
        #expect(!model.state.isLoaded)
        await answers.setFailing(false)
        await model.refresh()
        #expect(!model.state.loadFailed)
        #expect(model.state.sections[0].domain.accuracyText == "100%")
        // 再読込に失敗しても、前回の集計は残す
        await answers.setFailing(true)
        await model.refresh()
        #expect(model.state.loadFailed)
        #expect(model.state.sections[0].domain.accuracyText == "100%")
    }
}

// MARK: - Support

private func definition(_ id: ExamID) throws -> ExamDefinition { try SelectionFixtures.content(id).definition }

private func outcomes(_ sub: String, correct: Int, wrong: Int) -> [AnswerOutcome] {
    // サブ項目 ID の先頭がドメインの番号(NET.x は test-beta のドメイン 2)
    let domain = sub.hasPrefix("NET.") ? 2 : Int(sub.prefix { $0 != "." }) ?? 0
    return Array(repeating: AnswerOutcome(domain: domain, subObjective: sub, isCorrect: true), count: correct)
        + Array(repeating: AnswerOutcome(domain: domain, subObjective: sub, isCorrect: false), count: wrong)
}

private actor AnalyticsAnswers: AnswerHistoryRepository {
    private let stored: [ExamID: [AnswerOutcome]]
    private var failing = false
    private(set) var requested: [ExamID] = []
    init(_ stored: [ExamID: [AnswerOutcome]]) { self.stored = stored }
    func setFailing(_ value: Bool) { failing = value }
    func outcomes(examID: ExamID) async throws(PersistenceError) -> [AnswerOutcome] {
        requested.append(examID)
        if failing { throw .saveFailed("test") }
        return stored[examID] ?? []
    }
    func answers(examID: ExamID) throws(PersistenceError) -> [AnswerFact] { [] }
    func record(_ answer: AnswerFact) throws(PersistenceError) {}
    func practiceHistory(examID: ExamID, now: Date) throws(PersistenceError) -> PracticeHistory { .init() }
    func markServed(questionIDs: [String], examID: ExamID, at date: Date) throws(PersistenceError) {}
    func setFlag(_ flagged: Bool, questionID: String, examID: ExamID, at date: Date) throws(PersistenceError) {}
}
