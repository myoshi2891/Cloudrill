import Foundation

/// vendors.schema.json#/$defs/Vendor
public struct Vendor: Codable, Hashable, Sendable, Identifiable {
    public var id: String
    public var name: String
    /// 商標の表示(LG-04)
    public var trademarkNotice: LocalizedText
    /// 出典ライセンスの既定値
    public var defaultReferenceLicense: License
}

/// vendors.schema.json(vendors.yaml)
public struct VendorsFile: Codable, Hashable, Sendable {
    public var vendors: [Vendor]
}
