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

/// catalog.schema.json#/$defs/CatalogStatus(構造語彙。未知の値はデコードエラー)
public enum CatalogStatus: String, Codable, Hashable, Sendable, CaseIterable {
    /// 配信中
    case available
    /// 一覧に表示するが、取得はできない
    case comingSoon
    /// 新規には表示せず、取得済みの端末でだけ閲覧できる
    case retired
}
