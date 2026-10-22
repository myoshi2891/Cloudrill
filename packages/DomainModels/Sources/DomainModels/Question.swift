import Foundation

/// question.schema.json(1ファイル1問)
public struct Question: Codable, Hashable, Sendable, Identifiable {
    public var id: String
    public var revision: Int
    public var examGuideVersion: String
    public var domain: Int
    public var subObjective: String
    /// ケース問題でなければ nil(JSON では null)
    public var caseStudy: CaseStudyID?
    public var type: QuestionType
    public var difficulty: Int
    public var wafPillars: [WAFPillarID]
    public var keywords: [String]
    /// 収録先の模試番号。練習専用なら空
    public var examSets: [Int]
    public var stem: LocalizedText
    public var choices: [Choice]
    public var references: [Reference]

    public init(
        id: String, revision: Int, examGuideVersion: String, domain: Int, subObjective: String, caseStudy: CaseStudyID?,
        type: QuestionType, difficulty: Int, wafPillars: [WAFPillarID], keywords: [String], examSets: [Int],
        stem: LocalizedText, choices: [Choice], references: [Reference]
    ) {
        self.id = id
        self.revision = revision
        self.examGuideVersion = examGuideVersion
        self.domain = domain
        self.subObjective = subObjective
        self.caseStudy = caseStudy
        self.type = type
        self.difficulty = difficulty
        self.wafPillars = wafPillars
        self.keywords = keywords
        self.examSets = examSets
        self.stem = stem
        self.choices = choices
        self.references = references
    }

    public var correctChoiceIDs: [String] {
        choices.filter(\.isCorrect).map(\.id)
    }
}

/// common.schema.json#/$defs/QuestionKind(構造語彙。未知の値はデコードエラー)
public enum QuestionKind: String, Codable, Hashable, Sendable, CaseIterable {
    case single
    case multiple
}

/// question.schema.json#/$defs/QuestionType
/// JSON の `kind` で分岐する: `{"kind":"single"}` / `{"kind":"multiple","count":2}`
public enum QuestionType: Hashable, Sendable {
    case single
    case multiple(count: Int)

    public var requiredSelections: Int {
        switch self {
        case .single: 1
        case let .multiple(count): count
        }
    }

    /// 出題形式(exam.yaml の format.questionKinds と照合する)
    public var kind: QuestionKind {
        switch self {
        case .single: .single
        case .multiple: .multiple
        }
    }
}

extension QuestionType: Codable {
    private enum CodingKeys: String, CodingKey {
        case kind
        case count
    }

    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let kind = try container.decode(QuestionKind.self, forKey: .kind)
        switch kind {
        case .single:
            // Schema と同じく、single に count があればエラーにする
            guard !container.contains(.count) else {
                throw DecodingError.dataCorruptedError(
                    forKey: .count, in: container, debugDescription: "single の問題は count を持てません"
                )
            }
            self = .single
        case .multiple:
            let count = try container.decode(Int.self, forKey: .count)
            guard count >= 2 else {
                throw DecodingError.dataCorruptedError(
                    forKey: .count, in: container, debugDescription: "multiple の count は 2 以上が必要です(\(count))"
                )
            }
            self = .multiple(count: count)
        }
    }

    public func encode(to encoder: any Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        switch self {
        case .single:
            try container.encode(QuestionKind.single, forKey: .kind)
        case let .multiple(count):
            try container.encode(QuestionKind.multiple, forKey: .kind)
            try container.encode(count, forKey: .count)
        }
    }
}

/// question.schema.json#/$defs/Choice
public struct Choice: Hashable, Sendable, Identifiable {
    public var id: String
    public var text: LocalizedText
    public var isCorrect: Bool
    public var rationale: LocalizedText
    /// 誤答の分類。正解の選択肢では空(JSON では省略可)
    public var mistakeTags: [MistakeTag]

    public init(id: String, text: LocalizedText, isCorrect: Bool, rationale: LocalizedText, mistakeTags: [MistakeTag] = []) {
        self.id = id
        self.text = text
        self.isCorrect = isCorrect
        self.rationale = rationale
        self.mistakeTags = mistakeTags
    }
}

extension Choice: Codable {
    private enum CodingKeys: String, CodingKey {
        case id, text, isCorrect, rationale, mistakeTags
    }

    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(String.self, forKey: .id)
        text = try container.decode(LocalizedText.self, forKey: .text)
        isCorrect = try container.decode(Bool.self, forKey: .isCorrect)
        rationale = try container.decode(LocalizedText.self, forKey: .rationale)
        mistakeTags = try container.decodeIfPresent([MistakeTag].self, forKey: .mistakeTags) ?? []
    }

    public func encode(to encoder: any Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(id, forKey: .id)
        try container.encode(text, forKey: .text)
        try container.encode(isCorrect, forKey: .isCorrect)
        try container.encode(rationale, forKey: .rationale)
        if !mistakeTags.isEmpty {
            try container.encode(mistakeTags, forKey: .mistakeTags)
        }
    }
}
