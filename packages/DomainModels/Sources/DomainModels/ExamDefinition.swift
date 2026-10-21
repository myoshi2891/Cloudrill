import Foundation

/// exam.schema.json#/$defs/Scoring の policy(構造語彙。未知の値はデコードエラー)
public enum ScoringPolicyKind: String, Codable, Hashable, Sendable, CaseIterable {
    case allOrNothing
}

/// exam.schema.json(exams/<examID>/exam.yaml)
public struct ExamDefinition: Codable, Hashable, Sendable, Identifiable {
    public var id: ExamID
    public var vendor: VendorID
    public var name: LocalizedText
    /// 画面の狭い場所での表示用(例: PCA)
    public var shortName: String
    public var guideVersion: String
    public var guideURL: URL
    public var format: ExamFormat
    public var scoring: ScoringConfig
    /// id は 1 から始まる連番(CI-12)
    public var domains: [DomainDefinition]
    public var features: ExamFeatures
    public var taxonomies: ExamTaxonomies
    /// ケーススタディの表示順。ケースのない試験では空
    public var caseStudies: [CaseStudyID]

    /// サブ項目 ID → ドメイン番号。CI-12 で一意性を確認済みであることを前提にする(重複時は先のドメインを採用する)。
    public var domainBySubObjective: [String: Int] {
        var result: [String: Int] = [:]
        for domain in domains {
            for sub in domain.subObjectives where result[sub.id] == nil {
                result[sub.id] = domain.id
            }
        }
        return result
    }
}

/// exam.schema.json#/$defs/Format
public struct ExamFormat: Codable, Hashable, Sendable {
    public var durationMinutes: Int
    public var officialQuestionCount: CountRange
    public var questionKinds: [QuestionKind]
    public var mockExam: MockExamFormat
}

/// exam.schema.json#/$defs/Format の officialQuestionCount
public struct CountRange: Codable, Hashable, Sendable {
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
public struct ScoringConfig: Codable, Hashable, Sendable {
    public var policy: ScoringPolicyKind
}

/// exam.schema.json#/$defs/Domain
public struct DomainDefinition: Codable, Hashable, Sendable, Identifiable {
    public var id: Int
    public var name: LocalizedText
    public var weight: Double
    public var subObjectives: [SubObjectiveDefinition]
}

/// exam.schema.json#/$defs/SubObjective
public struct SubObjectiveDefinition: Codable, Hashable, Sendable, Identifiable {
    public var id: String
    public var name: LocalizedText
}

/// exam.schema.json#/$defs/Features。無効な機能のコンテンツは置けない(CI-12)。
/// 機能を追加したときに古い exam.json も読めるよう、フラグがなければ false として読む。
public struct ExamFeatures: Codable, Hashable, Sendable {
    public var caseStudies: Bool
    public var docs: Bool
    public var flashcards: Bool
    public var decisionTrees: Bool
    public var keywordDrills: Bool

    private enum CodingKeys: String, CodingKey {
        case caseStudies
        case docs
        case flashcards
        case decisionTrees
        case keywordDrills
    }

    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        caseStudies = try container.decodeIfPresent(Bool.self, forKey: .caseStudies) ?? false
        docs = try container.decodeIfPresent(Bool.self, forKey: .docs) ?? false
        flashcards = try container.decodeIfPresent(Bool.self, forKey: .flashcards) ?? false
        decisionTrees = try container.decodeIfPresent(Bool.self, forKey: .decisionTrees) ?? false
        keywordDrills = try container.decodeIfPresent(Bool.self, forKey: .keywordDrills) ?? false
    }
}

/// exam.schema.json#/$defs/Taxonomies
public struct ExamTaxonomies: Codable, Hashable, Sendable {
    /// WAF のない試験では空
    public var wafPillars: [TaxonomyEntry<WAFPillarID>]
}

/// 試験語彙の ID と表示名(例: exam.schema.json#/$defs/WAFPillar)
public struct TaxonomyEntry<ID: StringIdentifier>: Codable, Hashable, Sendable, Identifiable {
    public var id: ID
    public var name: LocalizedText
}
