import DomainModels

/// 出題の範囲
public enum PracticeScope: Hashable, Sendable {
    case all
    /// 直近の解答が不正解の問題
    case wrongOnly
    /// 解答したことがない問題
    case unanswered
    case flagged
}

public enum PracticeCount: Hashable, Sendable {
    case fixed(Int)
    case all
}

public enum SelectionStrategy: Hashable, Sendable {
    case random
    /// ドメイン番号 → 理解度 `score_d`(0〜1。Readiness の `DomainReadiness.score`)
    case weaknessFirst(domainScores: [Int: Double])
}

/// 練習の出題条件。異なる項目どうしは AND、同じ項目の中は OR。空の集合と nil は「絞り込まない」
public struct PracticeCriteria: Hashable, Sendable {
    public var domains: Set<Int>
    public var subObjectives: Set<String>
    public var caseStudies: Set<CaseStudyID>
    public var difficulty: ClosedRange<Int>?
    public var scope: PracticeScope
    public var count: PracticeCount
    public var strategy: SelectionStrategy

    public init(
        domains: Set<Int> = [],
        subObjectives: Set<String> = [],
        caseStudies: Set<CaseStudyID> = [],
        difficulty: ClosedRange<Int>? = nil,
        scope: PracticeScope = .all,
        count: PracticeCount = .fixed(10),
        strategy: SelectionStrategy = .random
    ) {
        self.domains = domains
        self.subObjectives = subObjectives
        self.caseStudies = caseStudies
        self.difficulty = difficulty
        self.scope = scope
        self.count = count
        self.strategy = strategy
    }
}
