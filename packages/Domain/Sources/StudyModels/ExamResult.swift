import DomainModels

/// 正答数と出題数
public struct ScoreTally: Hashable, Sendable {
    public var correct: Int
    public var total: Int

    public init(correct: Int, total: Int) {
        self.correct = correct
        self.total = total
    }

    /// 出題数が 0 なら nil(0% と区別する)
    public var ratio: Double? { total == 0 ? nil : Double(correct) / Double(total) }
}

/// 模試の採点結果
public struct ExamResult: Hashable, Sendable {
    public var total: ScoreTally
    /// ExamDefinition の全ドメインをキーに持つ(出題がないドメインは 0/0)
    public var byDomain: [Int: ScoreTally]
    /// ケース機能が無効な試験では空
    public var byCaseStudy: [CaseStudyID: ScoreTally]
    public var unansweredCount: Int

    public init(total: ScoreTally, byDomain: [Int: ScoreTally], byCaseStudy: [CaseStudyID: ScoreTally], unansweredCount: Int) {
        self.total = total
        self.byDomain = byDomain
        self.byCaseStudy = byCaseStudy
        self.unansweredCount = unansweredCount
    }
}
