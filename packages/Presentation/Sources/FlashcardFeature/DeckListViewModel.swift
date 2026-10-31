import Foundation
import Observation
import AppCore
import DomainModels
import DomainInterfaces
import StudyModels

/// デッキ一覧(SCR-030、FR-CARD-01)の1行
public struct Deck: Hashable, Sendable, Identifiable {
    public var kind: DeckKind
    /// ドメイン・サブ項目は試験定義の名前。すべて・間違えた問題は nil(View が文言を出す)
    public var title: LocalizedText?
    /// 試験定義でのドメインの位置(配色用)
    public var domainIndex: Int?
    public var total: Int
    public var dueToday: Int
    public var id: DeckID { kind.id }
}

@MainActor @Observable public final class DeckListViewModel {
    public struct State {
        public var isLoading = false
        public var isLoaded = false
        public var alert: String?
        public var decks: [Deck] = []
    }
    public private(set) var state = State()
    /// `features.flashcards` が無効な試験ではカードを読み込まない
    public var isAvailable: Bool { content.definition.features.flashcards }
    private let content: any ExamContentProvider
    private let cards: any CardStateRepository
    private let settings: any SettingsRepository
    private let time: any TimeSource
    private let calendar: Calendar
    private let router: AppRouter

    public init(content: any ExamContentProvider, cards: any CardStateRepository, settings: any SettingsRepository,
                time: any TimeSource, calendar: Calendar, router: AppRouter) {
        self.content = content; self.cards = cards; self.settings = settings
        self.time = time; self.calendar = calendar; self.router = router
    }

    public func refresh() async {
        guard isAvailable, !state.isLoading else { return }
        state.isLoading = true; state.alert = nil
        defer { state.isLoading = false }
        do {
            let examID = content.definition.id
            let library = try await CardLibrary.load(content: content, cards: cards)
            let preference = try await settings.preference(examID: examID)
            let now = time.now()
            let today = try await cards.todayCounts(examID: examID, calendar: calendar, now: now)
            state.decks = decks(library: library) { kind in
                library.queue(for: kind, preference: preference, today: today, calendar: calendar, now: now).cardIDs.count
            }
            state.isLoaded = true
        } catch { state.alert = "card.loadFailed" }
    }

    public func open(_ deck: Deck) { router.open(.cardSession(deck.id)) }

    /// すべて → ドメイン・サブ項目(試験定義の順) → 間違えた問題。カードのないデッキは出さない
    private func decks(library: CardLibrary, dueToday: (DeckKind) -> Int) -> [Deck] {
        guard !library.entries.isEmpty else { return [] }
        func deck(_ kind: DeckKind, title: LocalizedText?, domainIndex: Int?) -> Deck? {
            let total = library.entries(in: kind).count
            return total == 0 ? nil : Deck(kind: kind, title: title, domainIndex: domainIndex, total: total, dueToday: dueToday(kind))
        }
        var result = [deck(.all, title: nil, domainIndex: nil)].compactMap { $0 }
        for (index, domain) in content.definition.domains.enumerated() {
            guard let domainDeck = deck(.domain(domain.id), title: domain.name, domainIndex: index) else { continue }
            result.append(domainDeck)
            result += domain.subObjectives.compactMap { sub in
                deck(.subObjective(sub.id), title: LocalizedText(ja: "\(sub.id) \(sub.name.ja)", en: sub.name.en.map { "\(sub.id) \($0)" }),
                     domainIndex: index)
            }
        }
        if let mistakes = deck(.mistakes, title: nil, domainIndex: nil) { result.append(mistakes) }
        return result
    }
}
