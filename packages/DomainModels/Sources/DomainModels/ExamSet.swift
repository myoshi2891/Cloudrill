import Foundation

public enum ExamSetStatus: String, Codable, Hashable, Sendable {
    case draft
    case complete
}

public enum ExamLevel: String, Codable, Hashable, Sendable {
    case basic
    case standard
    case advanced
}

/// exam-sets.schema.json#/$defs/ExamSet
public struct ExamSet: Codable, Hashable, Sendable, Identifiable {
    public var id: Int
    public var status: ExamSetStatus
    public var level: ExamLevel
    /// ちょうど 2 つ
    public var caseStudies: [CaseStudyID]
    public var questionIDs: [String]
}

/// exam-sets.schema.json(exam-sets.yaml)
public struct ExamSetsFile: Codable, Hashable, Sendable {
    public var examSets: [ExamSet]
}

/// weights.schema.json(weights.yaml)。JSON のキー "1"〜"6" は Int キーとしてデコードされる。
public struct DomainWeights: Codable, Hashable, Sendable {
    public var examGuideVersion: String
    public var weights: [Int: Double]
}
