import Foundation

/// catalog.schema.json(CDN の /catalog.json。DDD 4.8)。`generatedAt` のデコードには `ContentDecoder.make()`(ISO 8601)を使う。
/// カタログには署名を付けない。改ざんされても、manifest の署名の検証と版の巻き戻しの拒否で防げる。
public struct Catalog: Codable, Hashable, Sendable {
    public var formatVersion: Int
    public var generatedAt: Date
    public var exams: [CatalogEntry]
}

/// catalog.schema.json#/$defs/CatalogEntry
public struct CatalogEntry: Codable, Hashable, Sendable, Identifiable {
    public var id: ExamID
    public var vendor: VendorID
    public var name: LocalizedText
    public var shortName: String
    public var status: CatalogStatus
    /// まだパックを配信していなければ nil
    public var latestPackVersion: String?
    /// latestPackVersion の manifest の minAppVersion。パックがなければ nil
    public var minAppVersion: String?
    public var productIDs: [String]
}

// latestPackVersion・minAppVersion は Schema で必須(null 可)。キーの欠落はデコードエラー、エンコードでは null を書く
extension CatalogEntry {
    private enum CodingKeys: String, CodingKey {
        case id, vendor, name, shortName, status, latestPackVersion, minAppVersion, productIDs
    }

    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(ExamID.self, forKey: .id)
        vendor = try container.decode(VendorID.self, forKey: .vendor)
        name = try container.decode(LocalizedText.self, forKey: .name)
        shortName = try container.decode(String.self, forKey: .shortName)
        status = try container.decode(CatalogStatus.self, forKey: .status)
        latestPackVersion = try container.decodeRequiredNullable(String.self, forKey: .latestPackVersion)
        minAppVersion = try container.decodeRequiredNullable(String.self, forKey: .minAppVersion)
        productIDs = try container.decode([String].self, forKey: .productIDs)
    }

    public func encode(to encoder: any Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(id, forKey: .id)
        try container.encode(vendor, forKey: .vendor)
        try container.encode(name, forKey: .name)
        try container.encode(shortName, forKey: .shortName)
        try container.encode(status, forKey: .status)
        try container.encode(latestPackVersion, forKey: .latestPackVersion)
        try container.encode(minAppVersion, forKey: .minAppVersion)
        try container.encode(productIDs, forKey: .productIDs)
    }
}

/// catalog.schema.json#/$defs/CatalogStatus(構造語彙。未知の値はデコードエラー)
public enum CatalogStatus: String, Codable, Hashable, Sendable, CaseIterable {
    /// 配信中
    case available
    /// 一覧に表示するが、取得はできない
    case comingSoon
    /// 新規には表示せず、取得済みの端末でだけ閲覧できる
    case retired
}
