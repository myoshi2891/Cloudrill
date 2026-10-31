import Foundation
import AppCore
import DomainModels
import DomainInterfaces
import StudyModels
import FSRS

/// デッキの種類。`DeckID.rawValue` に `all`・`domain:<n>`・`sub:<id>`・`mistakes` として符号化する。
public enum DeckKind: Hashable, Sendable {
    case all, domain(Int), subObjective(String), mistakes

    public var id: DeckID {
        switch self {
        case .all: "all"
        case .domain(let id): DeckID(rawValue: "domain:\(id)")
        case .subObjective(let id): DeckID(rawValue: "sub:\(id)")
        case .mistakes: "mistakes"
        }
    }

    public init?(id: DeckID) {
        let raw = id.rawValue
        if raw == "all" { self = .all; return }
        if raw == "mistakes" { self = .mistakes; return }
        if raw.hasPrefix("domain:"), let domain = Int(raw.dropFirst("domain:".count)) { self = .domain(domain); return }
        if raw.hasPrefix("sub:"), raw.count > "sub:".count { self = .subObjective(String(raw.dropFirst("sub:".count))); return }
        return nil
    }
}

/// 学習対象の1枚。コンテンツのカードか、間違えた問題から作ったカード(`Q:<questionID>`)のどちらか。
struct CardEntry: Hashable, Sendable {
    static let questionPrefix = "Q:"
    let id: String
    let domain: Int
    let subObjective: String
    let flashcard: Flashcard?
    var questionID: String? { id.hasPrefix(Self.questionPrefix) ? String(id.dropFirst(Self.questionPrefix.count)) : nil }

    func belongs(to deck: DeckKind) -> Bool {
        switch deck {
        case .all: true
        case .domain(let id): domain == id
        case .subObjective(let id): subObjective == id
        case .mistakes: questionID != nil
        }
    }
}

/// 現在の試験のカードと学習状態。デッキ一覧と学習画面で同じ規則のキューを作る。
struct CardLibrary: Sendable {
    /// コンテンツの順、続いて `Q:` カードを期限順に並べる
    let entries: [CardEntry]
    let states: [String: FSRSCard]

    static func load(content: any ExamContentProvider, cards: any CardStateRepository) async throws -> CardLibrary {
        let examID = content.definition.id
        let flashcards = try await content.flashcards()
        let scheduled = try await cards.scheduledCards(examID: examID)
        // 索引にない問題(パックから削除された問題)のカードは出さない
        let index = Dictionary(content.questionIndex.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
        let contentEntries = flashcards.map {
            CardEntry(id: $0.id, domain: $0.domain, subObjective: $0.subObjective, flashcard: $0)
        }
        let questionEntries: [CardEntry] = scheduled.compactMap { item in
            guard item.id.hasPrefix(CardEntry.questionPrefix),
                  let question = index[String(item.id.dropFirst(CardEntry.questionPrefix.count))] else { return nil }
            return CardEntry(id: item.id, domain: question.domain, subObjective: question.subObjective, flashcard: nil)
        }
        let states = Dictionary(scheduled.map { ($0.id, $0.card) }, uniquingKeysWith: { first, _ in first })
        return CardLibrary(entries: contentEntries + questionEntries, states: states)
    }

    func entries(in deck: DeckKind) -> [CardEntry] { entries.filter { $0.belongs(to: deck) } }

    /// 1日の上限は試験全体の今日の実績から差し引く(デッキごとに上限を増やさない)。
    func queue(for deck: DeckKind, preference: ExamPreference, today: (introduced: Int, reviewed: Int),
               calendar: Calendar, now: Date) -> DailyQueue {
        let members = entries(in: deck)
        let reviews = members.compactMap { entry in
            states[entry.id].flatMap { $0.phase == .new ? nil : ScheduledCard(id: entry.id, card: $0) }
        }
        let newIDs = members.filter { states[$0.id].map { $0.phase == .new } ?? true }.map(\.id)
        return DailyQueueBuilder(calendar: calendar).build(
            reviewCandidates: reviews, newCardIDs: newIDs,
            limits: DailyLimits(newCards: preference.dailyNewCards, reviews: preference.dailyReviewLimit),
            introducedToday: today.introduced, reviewedToday: today.reviewed, now: now)
    }
}

extension CardStateRepository {
    /// 注入した Calendar での今日の学習実績
    func todayCounts(examID: ExamID, calendar: Calendar, now: Date) async throws -> (introduced: Int, reviewed: Int) {
        let start = calendar.startOfDay(for: now)
        let end = calendar.date(byAdding: .day, value: 1, to: start) ?? start.addingTimeInterval(86_400)
        return try await reviewCount(examID: examID, on: DateInterval(start: start, end: end))
    }
}
