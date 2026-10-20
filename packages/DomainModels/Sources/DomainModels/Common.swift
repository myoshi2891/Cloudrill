import Foundation

/// common.schema.json#/$defs/LocalizedText
/// `ja` は必須。`en` は任意(欠落は CI-11 の warning)。
public struct LocalizedText: Codable, Hashable, Sendable {
    public var ja: String
    public var en: String?

    public init(ja: String, en: String? = nil) {
        self.ja = ja
        self.en = en
    }

    /// 指定言語の文字列。`en` がなければ `ja` にフォールバックする。
    public func text(preferEnglish: Bool) -> String {
        guard preferEnglish, let en, !en.isEmpty else { return ja }
        return en
    }
}

/// common.schema.json#/$defs/CaseStudyID
public enum CaseStudyID: String, Codable, Hashable, Sendable, CaseIterable {
    case ehr
    case altostrat
    case cymbal
    case knightMotives
}

/// common.schema.json#/$defs/WAFPillar
public enum WAFPillar: String, Codable, Hashable, Sendable, CaseIterable {
    case operationalExcellence
    case security
    case reliability
    case costOptimization
    case performance
    case sustainability
}

/// common.schema.json#/$defs/MistakeTag
public enum MistakeTag: String, Codable, Hashable, Sendable, CaseIterable {
    case cost
    case opsOverhead
    case compliance
    case scalability
    case availability
    case latency
    case requirementMismatch
    case deprecated
}

/// common.schema.json#/$defs/License
public enum License: String, Codable, Hashable, Sendable, CaseIterable {
    case ccBy40 = "CC-BY-4.0"
    case apache20 = "Apache-2.0"
    case linkOnly = "link-only"
}

/// common.schema.json#/$defs/Reference
public struct Reference: Codable, Hashable, Sendable {
    public var title: String
    public var url: URL
    public var license: License

    public init(title: String, url: URL, license: License) {
        self.title = title
        self.url = url
        self.license = license
    }
}

/// コンテンツ JSON 用のデコーダ(日付は ISO 8601)。
public enum ContentDecoder {
    public static func make() -> JSONDecoder {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return decoder
    }
}
