import Foundation
import DomainModels

/// 学習のモード(BDD 5.3)
public enum StudyMode: String, Codable, Hashable, Sendable, CaseIterable {
    case exam
    case practice
    case drill
}

/// 解答1件の事実。準備度や出題選択は、この記録から計算する(BDD 5.3)。
/// 問題の内容が改訂されても集計できるよう、解答時点のドメインとサブ項目を持つ。
public struct AnswerFact: Hashable, Sendable {
    public var examID: ExamID
    public var questionID: String
    public var questionRevision: Int
    public var domain: Int
    public var subObjective: String
    public var caseStudy: CaseStudyID?
    public var selection: AnswerSelection
    public var isCorrect: Bool
    public var mode: StudyMode
    public var answeredAt: Date
    public var elapsedSeconds: Int

    public init(
        examID: ExamID, questionID: String, questionRevision: Int, domain: Int, subObjective: String,
        caseStudy: CaseStudyID?, selection: AnswerSelection, isCorrect: Bool, mode: StudyMode,
        answeredAt: Date, elapsedSeconds: Int
    ) {
        self.examID = examID
        self.questionID = questionID
        self.questionRevision = questionRevision
        self.domain = domain
        self.subObjective = subObjective
        self.caseStudy = caseStudy
        self.selection = selection
        self.isCorrect = isCorrect
        self.mode = mode
        self.answeredAt = answeredAt
        self.elapsedSeconds = elapsedSeconds
    }
}
