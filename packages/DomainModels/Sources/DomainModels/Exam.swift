import Foundation

/// common.schema.json#/$defs/QuestionKind(構造語彙)
public enum QuestionKind: String, Codable, Hashable, Sendable, CaseIterable {
    case single
    case multiple
}

/// exam.schema.json#/$defs/Scoring の policy(構造語彙)
public enum ScoringPolicyKind: String, Codable, Hashable, Sendable, CaseIterable {
    case allOrNothing
}

/// exam.schema.json(exams/<examID>/exam.yaml)
public struct Exam: Codable, Hashable, Sendable, Identifiable {
    public var id: ExamID
    public var vendor: VendorID
    public var name: LocalizedText
    /// 画面の狭い場所での表示用(例: PCA)
    public var shortName: String
    public var guideVersion: String
    public var guideURL: URL
    public var format: ExamFormat
    public var scoring: ExamScoring
    /// id は 1 から始まる連番(CI-12)
    public var domains: [ExamDomain]
    public var features: ExamFeatures
    public var taxonomies: ExamTaxonomies
    /// ケーススタディの表示順
    public var caseStudies: [CaseStudyID]
}

/// exam.schema.json#/$defs/Format
public struct ExamFormat: Codable, Hashable, Sendable {
    public var durationMinutes: Int
    public var officialQuestionCount: QuestionCountRange
    public var questionKinds: [QuestionKind]
    public var mockExam: MockExamFormat
}

/// exam.schema.json#/$defs/Format の officialQuestionCount
public struct QuestionCountRange: Codable, Hashable, Sendable {
    public var min: Int
    public var max: Int
}

/// exam.schema.json#/$defs/Format の mockExam
public struct MockExamFormat: Codable, Hashable, Sendable {
    public var questionCount: Int
    /// 模試の回数の上限(exam-sets の id は 1〜setCount)
    public var setCount: Int
    /// ケースがない試験では 0
    public var caseStudiesPerSet: Int
}

/// exam.schema.json#/$defs/Scoring
public struct ExamScoring: Codable, Hashable, Sendable {
    public var policy: ScoringPolicyKind
}

/// exam.schema.json#/$defs/Domain
public struct ExamDomain: Codable, Hashable, Sendable, Identifiable {
    public var id: Int
    public var name: LocalizedText
    public var weight: Double
    public var subObjectives: [ExamSubObjective]
}

/// exam.schema.json#/$defs/SubObjective
public struct ExamSubObjective: Codable, Hashable, Sendable, Identifiable {
    public var id: String
    public var name: LocalizedText
}

/// exam.schema.json#/$defs/Features。無効な機能のコンテンツは置けない(CI-12)。
public struct ExamFeatures: Codable, Hashable, Sendable {
    public var caseStudies: Bool
    public var docs: Bool
    public var flashcards: Bool
    public var decisionTrees: Bool
    public var keywordDrills: Bool
}

/// exam.schema.json#/$defs/Taxonomies
public struct ExamTaxonomies: Codable, Hashable, Sendable {
    /// WAF のない試験では空
    public var wafPillars: [WAFPillarEntry]
}

/// exam.schema.json#/$defs/WAFPillar(柱の ID と表示名)
public struct WAFPillarEntry: Codable, Hashable, Sendable, Identifiable {
    public var id: WAFPillarID
    public var name: LocalizedText
}
