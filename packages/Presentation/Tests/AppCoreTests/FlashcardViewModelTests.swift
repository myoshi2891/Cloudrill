import Foundation
import Testing
import Synchronization
import FlashcardFeature
import AppCore
import DomainModels
import DomainInterfaces
import DomainTestSupport
import StudyModels
import FSRS

@MainActor struct FlashcardViewModelTests {
    @Test func decksByDomainAndSubObjective() async throws {
        // Arrange: コンテンツ3枚(ドメイン1に2枚・ドメイン2に1枚)と、索引にある Q: カード1枚・索引にない Q: カード1枚
        let h = try FlashcardHarness(cards: [card("C1", 1, "1.1"), card("C2", 1, "1.2"), card("C3", 2, "2.1")],
                                     questions: [QuestionBuilder.single().with(\.id, "Q5").with(\.domain, 2).with(\.subObjective, "2.3").build()])
        await h.cards.setScheduled([("Q:Q5", .new(at: h.now)), ("Q:GONE", .new(at: h.now))])
        let model = h.deckList()
        // Act
        await model.refresh()
        // Assert
        #expect(model.state.decks.map(\.kind) == [.all, .domain(1), .subObjective("1.1"), .subObjective("1.2"),
                                                  .domain(2), .subObjective("2.1"), .subObjective("2.3"), .mistakes])
        #expect(model.state.decks.map(\.total) == [4, 2, 1, 1, 2, 1, 1, 1])
        #expect(model.state.decks.first?.dueToday == 4)
        #expect(model.state.decks.first { $0.kind == .domain(2) }?.title?.ja == h.content.definition.domains[1].name.ja)
        model.open(model.state.decks[1])
        #expect(h.router.selectedTab == .cards)
        #expect(h.router.path(for: .cards) == [.cardSession("domain:1")])
    }

    @Test func noMistakeDeckWithoutQuestionCards() async throws {
        let h = try FlashcardHarness(cards: [card("C1", 1, "1.1")])
        let model = h.deckList()
        await model.refresh()
        #expect(!model.state.decks.contains { $0.kind == .mistakes })
    }

    @Test func hiddenWhenFeatureDisabled() async throws {
        // Arrange: 生成済み fixture は変えず、テスト内で機能を無効にする
        let h = try FlashcardHarness("test-beta", cards: [card("C1", 1, "1.1")], flashcards: false)
        let model = h.deckList()
        // Act
        await model.refresh()
        let session = h.session("all")
        await session.start()
        // Assert
        #expect(!model.isAvailable)
        #expect(model.state.decks.isEmpty)
        #expect(h.content.flashcardReads == 0)
        #expect(session.state.phase == .empty)
    }

    @Test func queueFromDailyBuilder() async throws {
        // Arrange: 復習3枚(期限は R2 < R0 < R1)と新規5枚。新規の上限 4、今日すでに新規1枚
        let reviews = ["R0", "R1", "R2"]
        let news = (0..<5).map { "N\($0)" }
        let h = try FlashcardHarness(cards: (reviews + news).map { card($0, 1, "1.1") })
        await h.cards.setScheduled([("R0", try reviewed(daysAgo: 30)), ("R1", try reviewed(daysAgo: 20)), ("R2", try reviewed(daysAgo: 40))])
        await h.cards.setToday(introduced: 1, reviewed: 0)
        await h.settings.set(try ExamPreference(desiredRetention: 0.9, dailyNewCards: 4))
        let model = h.session("all")
        // Act
        await model.start()
        // Assert
        #expect(model.faces.map(\.id) == ["R2", "R0", "R1", "N0", "N1", "N2"])
        #expect(await h.cards.countedDay == DateInterval(start: h.calendar.startOfDay(for: h.now), duration: 86_400))
    }

    @Test func flipThenRate() async throws {
        let h = try FlashcardHarness(cards: [card("C1", 1, "1.1"), card("C2", 1, "1.1")])
        let model = h.session("sub:1.1")
        await model.start()
        // 裏を見る前の評価は受け付けない
        await model.rate(.good)
        #expect(await h.cards.applied.isEmpty)
        model.flip()
        h.time.advance(by: .seconds(5))
        await model.rate(.good)
        let expected = FSRSScheduler(parameters: try FSRSParameters()).review(.new(at: h.time.now()), rating: .good, at: h.time.now())
        #expect(await h.cards.applied.map(\.id) == ["C1"])
        #expect(await h.cards.applied.first?.outcome == expected)
        #expect(model.state.index == 1)
        #expect(!model.state.showsBack)
    }

    @Test func ratingButtonsShowIntervals() async throws {
        let h = try FlashcardHarness(cards: [card("C1", 1, "1.1")])
        let model = h.session("all")
        await model.start()
        #expect(model.intervals.isEmpty)
        model.flip()
        let intervals = model.intervals
        #expect(intervals.map(\.rating) == [.again, .hard, .good, .easy])
        #expect(intervals.prefix(3).map(\.interval.label) == ["1分", "6分", "10分"])
        guard case .days(let days) = intervals[3].interval else { Issue.record("Easy は日単位"); return }
        #expect(days >= 1)
    }

    @Test(arguments: [
        (59.0, CardInterval.minutes(1)), (600, .minutes(10)), (3_600, .hours(1)), (3 * 86_400, .days(3)),
        (60 * 86_400, .months(2)), (400 * 86_400, .years(1)),
    ])
    func intervalBuckets(seconds: Double, expected: CardInterval) {
        #expect(CardInterval(seconds: seconds) == expected)
    }

    @Test func finishShowsSummary() async throws {
        let h = try FlashcardHarness(cards: [card("C1", 1, "1.1"), card("C2", 1, "1.1")])
        h.router.open(.cardSession("all"))
        let model = h.session("all")
        await model.start()
        model.flip(); await model.rate(.again)
        model.flip(); await model.rate(.easy)
        #expect(model.state.phase == .finished)
        #expect(model.state.studied == 2)
        #expect(model.state.ratings == [.again: 1, .easy: 1])
        model.backToDecks()
        #expect(h.router.path(for: .cards).isEmpty)
    }

    @Test func questionCardShowsStemAndCorrectChoices() async throws {
        let question = QuestionBuilder.single(correct: "b").with(\.id, "Q7").build()
        let h = try FlashcardHarness(cards: [], questions: [question])
        await h.cards.setScheduled([("Q:Q7", .new(at: h.now))])
        let model = h.session("mistakes")
        await model.start()
        let face = try #require(model.current)
        #expect(face.front == question.stem)
        #expect(face.back.ja == question.choices.first { $0.id == "b" }?.text.ja)
        #expect(face.note?.ja == question.choices.first { $0.id == "b" }?.rationale.ja)
    }

    @Test func saveFailureKeepsPositionAndRetriesSameOutcome() async throws {
        let h = try FlashcardHarness(cards: [card("C1", 1, "1.1"), card("C2", 1, "1.1")])
        let model = h.session("all")
        await model.start()
        model.flip()
        let firstTry = h.time.now()
        await h.cards.failApply(true)
        await model.rate(.good)
        #expect(model.state.alert == "card.saveFailed")
        #expect(model.state.index == 0)
        #expect(model.state.showsBack)
        await h.cards.failApply(false)
        h.time.advance(by: .seconds(30))
        await model.rate(.good)
        #expect(await h.cards.applied.count == 1)
        #expect(await h.cards.applied.first?.outcome.reviewedAt == firstTry)
        #expect(model.state.index == 1)
        #expect(model.state.alert == nil)
    }

    @Test func rejectsRatingWhileSaving() async throws {
        let h = try FlashcardHarness(cards: [card("C1", 1, "1.1"), card("C2", 1, "1.1")])
        let model = h.session("all")
        await model.start()
        model.flip()
        await h.cards.pauseNextApply()
        let first = Task { await model.rate(.good) }
        await h.cards.waitForApply()
        await model.rate(.easy)
        await h.cards.resumeApply()
        await first.value
        #expect(await h.cards.applied.map(\.outcome.rating) == [.good])
        #expect(model.state.index == 1)
    }

    @Test func loadFailureCanRetry() async throws {
        let h = try FlashcardHarness(cards: [card("C1", 1, "1.1")])
        h.content.failFlashcards(true)
        let list = h.deckList(), model = h.session("all")
        await list.refresh(); await model.start()
        #expect(list.state.alert == "card.loadFailed")
        #expect(model.state.alert == "card.loadFailed")
        #expect(model.state.phase == .idle)
        h.content.failFlashcards(false)
        await list.refresh(); await model.start()
        #expect(list.state.decks.map(\.kind) == [.all, .domain(1), .subObjective("1.1")])
        #expect(model.state.phase == .studying)
    }

    @Test func deckIDRoundTrip() {
        for kind in [DeckKind.all, .domain(3), .subObjective("NET.1"), .mistakes] {
            #expect(DeckKind(id: kind.id) == kind)
        }
        #expect(DeckKind(id: "domain:x") == nil)
        #expect(DeckKind(id: "sub:") == nil)
    }
}

// MARK: - Support

private func card(_ id: String, _ domain: Int, _ sub: String) -> Flashcard {
    let json = """
    {"id":"\(id)","domain":\(domain),"subObjective":"\(sub)","front":{"ja":"表 \(id)","en":"Front \(id)"},
     "back":{"ja":"裏 \(id)"},"relatedQuestionIDs":[]}
    """
    // 固定の JSON なので失敗しない。失敗した場合はテストの記述の誤り
    do { return try JSONDecoder().decode(Flashcard.self, from: Data(json.utf8)) } catch { fatalError("\(error)") }
}

/// Easy で学習を始めた review 段階のカード(期限は数日後なので、daysAgo を十分に取れば今日の復習対象)
private func reviewed(daysAgo: Int) throws -> FSRSCard {
    let start = SelectionFixtures.now.addingTimeInterval(-Double(daysAgo) * 86_400)
    return FSRSScheduler(parameters: try FSRSParameters()).review(.new(at: start), rating: .easy, at: start).card
}

@MainActor private struct FlashcardHarness {
    let content: FlashcardContent
    let cards = FlashcardCards()
    let settings = FlashcardSettings()
    let time = ManualTimeSource(SelectionFixtures.now)
    let router = AppRouter()
    let calendar: Calendar = {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "Asia/Tokyo") ?? .gmt
        return calendar
    }()
    var now: Date { SelectionFixtures.now }
    init(_ id: ExamID = "test-alpha", cards: [Flashcard], questions: [Question] = [], flashcards: Bool = true) throws {
        var base = try ExamFixture(id)
        base.definition.features.flashcards = flashcards
        content = FlashcardContent(base: base, cards: cards, values: questions)
    }
    func deckList() -> DeckListViewModel {
        DeckListViewModel(content: content, cards: cards, settings: settings, time: time, calendar: calendar, router: router)
    }
    func session(_ deck: DeckID) -> CardSessionViewModel {
        CardSessionViewModel(content: content, deck: deck, cards: cards, settings: settings, time: time,
                             calendar: calendar, router: router)
    }
}

private final class FlashcardContent: ExamContentProvider, Sendable {
    let base: ExamFixture
    let cards: [Flashcard]
    let values: [Question]
    private let reads = Mutex(0)
    private let fails = Mutex(false)
    init(base: ExamFixture, cards: [Flashcard], values: [Question]) { self.base = base; self.cards = cards; self.values = values }
    var flashcardReads: Int { reads.withLock { $0 } }
    func failFlashcards(_ value: Bool) { fails.withLock { $0 = value } }
    var definition: ExamDefinition { base.definition }
    var vendor: Vendor { base.vendor }
    var packVersion: String { "1.0.0" }
    var questionIndex: [QuestionIndexEntry] { values.map {
        .init(id: $0.id, revision: $0.revision, domain: $0.domain, subObjective: $0.subObjective,
              caseStudy: $0.caseStudy, difficulty: $0.difficulty, kind: $0.type.kind, examSets: [])
    } }
    var examSets: [ExamSet] { [] }
    var docsIndex: [DocEntry] { [] }
    func questions(ids: [String]) async throws(ContentError) -> [Question] { values.filter { ids.contains($0.id) }.reversed() }
    func flashcards() async throws(ContentError) -> [Flashcard] {
        reads.withLock { $0 += 1 }
        if fails.withLock({ $0 }) { throw .fileMissing("flashcards") }
        return cards
    }
    func caseStudies() async throws(ContentError) -> [CaseStudy] { [] }
    func decisionTrees() async throws(ContentError) -> [DecisionTree] { [] }
    func keywordDrills() async throws(ContentError) -> [KeywordDrill] { [] }
    func docBody(for entry: DocEntry) async throws(ContentError) -> String { "" }
}

private actor FlashcardCards: CardStateRepository {
    var scheduled: [(id: String, card: FSRSCard)] = []
    var applied: [(id: String, outcome: ReviewOutcome)] = []
    var today = (introduced: 0, reviewed: 0)
    var countedDay: DateInterval?
    private var applyFails = false
    private var pauseApply = false
    private var continuation: CheckedContinuation<Void, Never>?
    private var observer: CheckedContinuation<Void, Never>?
    func setScheduled(_ value: [(String, FSRSCard)]) { scheduled = value.map { (id: $0.0, card: $0.1) } }
    func setToday(introduced: Int, reviewed: Int) { today = (introduced, reviewed) }
    func failApply(_ value: Bool) { applyFails = value }
    func pauseNextApply() { pauseApply = true }
    func waitForApply() async {
        if continuation != nil { return }
        await withCheckedContinuation { observer = $0 }
    }
    func resumeApply() { continuation?.resume(); continuation = nil }
    func card(id: String, examID: ExamID) throws(PersistenceError) -> FSRSCard? { scheduled.first { $0.id == id }?.card }
    func apply(_ outcome: ReviewOutcome, cardID: String, examID: ExamID) async throws(PersistenceError) {
        if pauseApply {
            pauseApply = false
            await withCheckedContinuation { continuation = $0; observer?.resume(); observer = nil }
        }
        if applyFails { throw .saveFailed("test") }
        applied.append((cardID, outcome))
    }
    func scheduledCards(examID: ExamID) throws(PersistenceError) -> [(id: String, card: FSRSCard)] { scheduled }
    func reviewCount(examID: ExamID, on day: DateInterval) throws(PersistenceError) -> (introduced: Int, reviewed: Int) {
        countedDay = day; return today
    }
    func addCardFromQuestion(questionID: String, examID: ExamID, at date: Date) throws(PersistenceError) {}
}

private actor FlashcardSettings: SettingsRepository {
    var value = ExamPreference.default
    func set(_ preference: ExamPreference) { value = preference }
    func settings() throws(PersistenceError) -> UserSettings { UserSettings() }
    func preference(examID: ExamID) throws(PersistenceError) -> ExamPreference { value }
    func save(settings: UserSettings, at date: Date) throws(PersistenceError) {}
    func save(preference: ExamPreference, examID: ExamID, at date: Date) throws(PersistenceError) {}
}
