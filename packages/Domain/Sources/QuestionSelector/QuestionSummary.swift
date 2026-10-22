import Foundation
import DomainModels

/// 出題選択に使う、問題の要約(問題の本文や選択肢は持たない)
public struct QuestionSummary: Hashable, Sendable {
    public var id: String
    public var domain: Int
    public var subObjective: String
    public var caseStudy: CaseStudyID?
    public var difficulty: Int
    public var kind: QuestionKind

    public init(id: String, domain: Int, subObjective: String, caseStudy: CaseStudyID?, difficulty: Int, kind: QuestionKind) {
        self.id = id
        self.domain = domain
        self.subObjective = subObjective
        self.caseStudy = caseStudy
        self.difficulty = difficulty
        self.kind = kind
    }
}

/// 練習の履歴(呼び出し側が解答の記録から作る)
public struct PracticeHistory: Sendable {
    /// 問題 ID → 直近の解答が正解か(解答したことがない問題はキーがない)
    public var lastResult: [String: Bool]
    public var flagged: Set<String>
    /// 問題 ID → 最後に出題した時刻
    public var lastServedAt: [String: Date]

    public init(lastResult: [String: Bool] = [:], flagged: Set<String> = [], lastServedAt: [String: Date] = [:]) {
        self.lastResult = lastResult
        self.flagged = flagged
        self.lastServedAt = lastServedAt
    }
}
