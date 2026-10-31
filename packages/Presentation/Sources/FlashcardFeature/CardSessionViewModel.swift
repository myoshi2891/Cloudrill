import Foundation
import Observation
import AppCore
import DomainModels
import DomainInterfaces
import StudyModels
import FSRS

/// 表示用のカード面。`Q:` カードは表が問題文、裏が正解の選択肢と理由
public struct CardFace: Hashable, Sendable, Identifiable {
    public var id: String
    public var domain: Int
    public var front: LocalizedText
    public var back: LocalizedText
    public var note: LocalizedText?
}

/// 評価ボタンに出す次の間隔(切り上げずに四捨五入。最小1分)
public enum CardInterval: Hashable, Sendable {
    case minutes(Int), hours(Int), days(Int), months(Int), years(Int)

    public init(seconds: TimeInterval) {
        let minutes = max(1, Int((seconds / 60).rounded()))
        let days = seconds / 86_400
        switch seconds {
        case ..<3_600: self = .minutes(minutes)
        case ..<86_400: self = .hours(max(1, Int((seconds / 3_600).rounded())))
        case ..<(30 * 86_400): self = .days(max(1, Int(days.rounded())))
        case ..<(365 * 86_400): self = .months(max(1, Int((days / 30).rounded())))
        default: self = .years(max(1, Int((days / 365).rounded())))
        }
    }

    public var label: String {
        let (key, value): (String.LocalizationValue, Int) = switch self {
        case .minutes(let n): ("card.interval.minutes", n)
        case .hours(let n): ("card.interval.hours", n)
        case .days(let n): ("card.interval.days", n)
        case .months(let n): ("card.interval.months", n)
        case .years(let n): ("card.interval.years", n)
        }
        return String(format: String(localized: key, bundle: .module), value)
    }
}

@MainActor @Observable public final class CardSessionViewModel {
    public struct State {
        public var phase: Phase = .idle
        public var isBusy = false
        public var alert: String?
        public var index = 0
        public var showsBack = false
        public var ratings: [Rating: Int] = [:]
        public var studied: Int { ratings.values.reduce(0, +) }
    }
    public enum Phase { case idle, studying, empty, finished }
    public private(set) var state = State()
    public private(set) var faces: [CardFace] = []
    public let deck: DeckID
    public var current: CardFace? { faces.indices.contains(state.index) ? faces[state.index] : nil }
    private let content: any ExamContentProvider
    private let cards: any CardStateRepository
    private let settings: any SettingsRepository
    private let time: any TimeSource
    private let calendar: Calendar
    private let router: AppRouter
    private var states: [String: FSRSCard] = [:]
    private var scheduler: FSRSScheduler?
    // 保存に失敗した評価は、同じ評価なら同じ結果(時刻を含む)で再試行する
    private var pending: (cardID: String, outcome: ReviewOutcome)?

    public init(content: any ExamContentProvider, deck: DeckID, cards: any CardStateRepository,
                settings: any SettingsRepository, time: any TimeSource, calendar: Calendar, router: AppRouter) {
        self.content = content; self.deck = deck; self.cards = cards; self.settings = settings
        self.time = time; self.calendar = calendar; self.router = router
    }

    public func start() async {
        guard !state.isBusy, state.phase == .idle else { return }
        state.isBusy = true; state.alert = nil
        defer { state.isBusy = false }
        guard content.definition.features.flashcards, let kind = DeckKind(id: deck) else { state.phase = .empty; return }
        do {
            let examID = content.definition.id
            let library = try await CardLibrary.load(content: content, cards: cards)
            let preference = try await settings.preference(examID: examID)
            let parameters = try FSRSParameters(desiredRetention: preference.desiredRetention)
            let now = time.now()
            let today = try await cards.todayCounts(examID: examID, calendar: calendar, now: now)
            let ids = library.queue(for: kind, preference: preference, today: today, calendar: calendar, now: now).cardIDs
            let faces = try await self.faces(for: ids, library: library)
            scheduler = FSRSScheduler(parameters: parameters)
            states = library.states; self.faces = faces
            state.phase = faces.isEmpty ? .empty : .studying
        } catch { state.alert = "card.loadFailed" }
    }

    public func flip() {
        guard !state.isBusy, state.phase == .studying else { return }
        state.showsBack = true
    }

    /// 裏面を表示しているときの、4つの評価それぞれの次の間隔
    public var intervals: [(rating: Rating, interval: CardInterval)] {
        guard state.showsBack, let current, let scheduler else { return [] }
        let now = time.now()
        let card = states[current.id] ?? .new(at: now)
        return Rating.allCases.map { rating in
            (rating, CardInterval(seconds: scheduler.review(card, rating: rating, at: now).card.due.timeIntervalSince(now)))
        }
    }

    public func rate(_ rating: Rating) async {
        guard !state.isBusy, state.phase == .studying, state.showsBack, let current, let scheduler else { return }
        state.isBusy = true; state.alert = nil
        defer { state.isBusy = false }
        let outcome: ReviewOutcome
        if let pending, pending.cardID == current.id, pending.outcome.rating == rating {
            outcome = pending.outcome
        } else {
            let now = time.now()
            outcome = scheduler.review(states[current.id] ?? .new(at: now), rating: rating, at: now)
        }
        pending = (current.id, outcome)
        do {
            try await cards.apply(outcome, cardID: current.id, examID: content.definition.id)
        } catch { state.alert = "card.saveFailed"; return }
        pending = nil
        states[current.id] = outcome.card
        state.ratings[rating, default: 0] += 1
        state.showsBack = false
        if state.index + 1 == faces.count { state.phase = .finished } else { state.index += 1 }
    }

    public func backToDecks() { router.setPath([], for: .cards) }

    /// キューの順に表示用の面を作る。`Q:` カードの問題本文は一括で取得し、件数と ID を確かめる
    private func faces(for ids: [String], library: CardLibrary) async throws -> [CardFace] {
        let entries = Dictionary(library.entries.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
        let questionIDs = ids.compactMap { entries[$0]?.questionID }
        var questions: [String: Question] = [:]
        if !questionIDs.isEmpty {
            let loaded = try await content.questions(ids: questionIDs)
            guard loaded.count == questionIDs.count, Set(loaded.map(\.id)) == Set(questionIDs) else {
                throw ContentError.unknownQuestionIDs(questionIDs)
            }
            questions = Dictionary(loaded.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
        }
        return try ids.map { id throws(ContentError) in
            guard let entry = entries[id] else { throw .unknownQuestionIDs([id]) }
            if let card = entry.flashcard {
                return CardFace(id: id, domain: card.domain, front: card.front, back: card.back, note: nil)
            }
            guard let questionID = entry.questionID, let question = questions[questionID] else { throw .unknownQuestionIDs([id]) }
            let correct = question.choices.filter(\.isCorrect)
            return CardFace(id: id, domain: question.domain, front: question.stem,
                            back: .joined(correct.map(\.text)), note: .joined(correct.map(\.rationale)))
        }
    }
}

private extension LocalizedText {
    /// 改行で連結する。英語は全件にあるときだけ連結する(一部だけ英語にしない)
    static func joined(_ texts: [LocalizedText]) -> LocalizedText {
        let english = texts.compactMap(\.en)
        return LocalizedText(ja: texts.map(\.ja).joined(separator: "\n"),
                             en: english.count == texts.count ? english.joined(separator: "\n") : nil)
    }
}
