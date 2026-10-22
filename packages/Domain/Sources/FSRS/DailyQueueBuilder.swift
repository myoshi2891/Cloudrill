import Foundation

/// 1日に出すカードの上限(利用者の設定)
public struct DailyLimits: Hashable, Sendable {
    public var newCards: Int
    public var reviews: Int

    public init(newCards: Int, reviews: Int) {
        self.newCards = newCards
        self.reviews = reviews
    }
}

/// 学習済みのカードと、その ID
public struct ScheduledCard: Hashable, Sendable {
    public var id: String
    public var card: FSRSCard

    public init(id: String, card: FSRSCard) {
        self.id = id
        self.card = card
    }
}

/// 今日のキュー。復習を先に、新規を後に出す
public struct DailyQueue: Hashable, Sendable {
    public var reviewCardIDs: [String]
    public var newCardIDs: [String]

    /// 出す順のすべてのカード
    public var cardIDs: [String] { reviewCardIDs + newCardIDs }
}

/// 1日の出題キューを作る(FR-CARD-05、BDD 6.5)。「今日」は注入した Calendar のタイムゾーンで決める。
public struct DailyQueueBuilder: Sendable {
    private let calendar: Calendar

    public init(calendar: Calendar) {
        self.calendar = calendar
    }

    /// - Parameters:
    ///   - reviewCandidates: 学習済みのカード。未学習(`.new`)のカードは対象外
    ///   - newCardIDs: まだ学習していないカード(コンテンツ側の順)
    ///   - introducedToday: 今日すでに学習を始めた新規カードの枚数
    ///   - reviewedToday: 今日すでに復習した枚数
    public func build(
        reviewCandidates: [ScheduledCard],
        newCardIDs: [String],
        limits: DailyLimits,
        introducedToday: Int,
        reviewedToday: Int,
        now: Date
    ) -> DailyQueue {
        let endOfToday = startOfTomorrow(after: now)
        let reviewCapacity = max(0, limits.reviews - reviewedToday)
        let newCapacity = max(0, limits.newCards - introducedToday)

        // 期限の古い順。同じ期限なら候補の順を保つ(結果を決定論にするため、元の位置で並べる)
        let reviews = reviewCandidates.enumerated()
            .filter { $0.element.card.phase != .new && $0.element.card.due < endOfToday }
            .sorted { ($0.element.card.due, $0.offset) < ($1.element.card.due, $1.offset) }
            .prefix(reviewCapacity)
            .map(\.element.id)

        return DailyQueue(reviewCardIDs: Array(reviews), newCardIDs: Array(newCardIDs.prefix(newCapacity)))
    }

    /// 明日の 0:00(Calendar のタイムゾーン)
    private func startOfTomorrow(after now: Date) -> Date {
        let startOfToday = calendar.startOfDay(for: now)
        // グレゴリオ暦では nil にならない。万一の場合も、24 時間後を使えば今日のカードを取りこぼさない
        return calendar.date(byAdding: .day, value: 1, to: startOfToday) ?? startOfToday.addingTimeInterval(86_400)
    }
}
