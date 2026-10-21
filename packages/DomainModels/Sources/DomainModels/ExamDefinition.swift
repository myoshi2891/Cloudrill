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

    public init(
        id: ExamID, vendor: VendorID, name: LocalizedText, shortName: String, guideVersion: String, guideURL: URL,
        format: ExamFormat, scoring: ScoringConfig, domains: [DomainDefinition], features: ExamFeatures,
        taxonomies: ExamTaxonomies, caseStudies: [CaseStudyID]
    ) {
        self.id = id
        self.vendor = vendor
        self.name = name
        self.shortName = shortName
        self.guideVersion = guideVersion
        self.guideURL = guideURL
        self.format = format
        self.scoring = scoring
        self.domains = domains
        self.features = features
        self.taxonomies = taxonomies
        self.caseStudies = caseStudies
    }

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

    public init(durationMinutes: Int, officialQuestionCount: CountRange, questionKinds: [QuestionKind], mockExam: MockExamFormat) {
        self.durationMinutes = durationMinutes
        self.officialQuestionCount = officialQuestionCount
        self.questionKinds = questionKinds
        self.mockExam = mockExam
    }
}

/// exam.schema.json#/$defs/Format の officialQuestionCount
public struct CountRange: Codable, Hashable, Sendable {
    public var min: Int
    public var max: Int

    public init(min: Int, max: Int) {
        self.min = min
        self.max = max
    }
}

/// exam.schema.json#/$defs/Format の mockExam
public struct MockExamFormat: Codable, Hashable, Sendable {
    public var questionCount: Int
    /// 模試の回数の上限(exam-sets の id は 1〜setCount)
    public var setCount: Int
    /// ケースがない試験では 0
    public var caseStudiesPerSet: Int

    public init(questionCount: Int, setCount: Int, caseStudiesPerSet: Int) {
        self.questionCount = questionCount
        self.setCount = setCount
        self.caseStudiesPerSet = caseStudiesPerSet
    }
}

/// exam.schema.json#/$defs/Scoring
public struct ScoringConfig: Codable, Hashable, Sendable {
    public var policy: ScoringPolicyKind

    public init(policy: ScoringPolicyKind) {
        self.policy = policy
    }
}

/// exam.schema.json#/$defs/Domain
public struct DomainDefinition: Codable, Hashable, Sendable, Identifiable {
    public var id: Int
    public var name: LocalizedText
    public var weight: Double
    public var subObjectives: [SubObjectiveDefinition]

    public init(id: Int, name: LocalizedText, weight: Double, subObjectives: [SubObjectiveDefinition]) {
        self.id = id
        self.name = name
        self.weight = weight
        self.subObjectives = subObjectives
    }
}

/// exam.schema.json#/$defs/SubObjective
public struct SubObjectiveDefinition: Codable, Hashable, Sendable, Identifiable {
    public var id: String
    public var name: LocalizedText

    public init(id: String, name: LocalizedText) {
        self.id = id
        self.name = name
    }
}

/// exam.schema.json#/$defs/Features。無効な機能のコンテンツは置けない(CI-12)。
/// 機能を追加したときに古い exam.json も読めるよう、フラグがなければ false として読む。
public struct ExamFeatures: Codable, Hashable, Sendable {
    public var caseStudies: Bool
    public var docs: Bool
    public var flashcards: Bool
    public var decisionTrees: Bool
    public var keywordDrills: Bool

    public init(caseStudies: Bool, docs: Bool, flashcards: Bool, decisionTrees: Bool, keywordDrills: Bool) {
        self.caseStudies = caseStudies
        self.docs = docs
        self.flashcards = flashcards
        self.decisionTrees = decisionTrees
        self.keywordDrills = keywordDrills
    }

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

    public init(wafPillars: [TaxonomyEntry<WAFPillarID>]) {
        self.wafPillars = wafPillars
    }
}

/// 試験語彙の ID と表示名(例: exam.schema.json#/$defs/WAFPillar)
public struct TaxonomyEntry<ID: StringIdentifier>: Codable, Hashable, Sendable, Identifiable {
    public var id: ID
    public var name: LocalizedText

    public init(id: ID, name: LocalizedText) {
        self.id = id
        self.name = name
    }
}
