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

extension Reference {
    /// `url` は SwiftUI の Link に渡すので、デコードの時点で https に限る。
    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        title = try container.decode(String.self, forKey: .title)
        url = try container.decodeHTTPSURL(forKey: .url)
        license = try container.decode(License.self, forKey: .license)
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

extension KeyedDecodingContainer {
    /// common.schema.json#/$defs/HttpsURL のうち、スキーム(小文字の https)とホストの有無を確認する。
    func decodeHTTPSURL(forKey key: Key) throws -> URL {
        let url = try decode(URL.self, forKey: key)
        guard url.scheme == "https", let host = url.host(), !host.isEmpty else {
            throw DecodingError.dataCorruptedError(forKey: key, in: self, debugDescription: "https の URL ではありません")
        }
        return url
    }

    /// Schema で必須かつ null 可(`required` + `anyOf [..., null]`)の項目を読む。
    /// null なら nil、キーがなければ keyNotFound(合成の Decodable は Optional のキーの欠落を許してしまうため)。
    func decodeRequiredNullable<T: Decodable>(_ type: T.Type, forKey key: Key) throws -> T? {
        guard contains(key) else {
            throw DecodingError.keyNotFound(
                key, .init(codingPath: codingPath, debugDescription: "\(key.stringValue) は必須です(値がなければ null)")
            )
        }
        return try decodeIfPresent(type, forKey: key)
    }
}
