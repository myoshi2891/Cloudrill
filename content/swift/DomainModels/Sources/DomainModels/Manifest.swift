import Foundation

/// manifest.schema.json。`createdAt` のデコードには `ContentDecoder.make()`(ISO 8601)を使う。
public struct Manifest: Codable, Hashable, Sendable {
    public var packVersion: String
    public var examGuideVersion: String
    public var minAppVersion: String
    public var createdAt: Date
    public var files: [ManifestFile]
    /// Ed25519 署名(Base64)
    public var signature: String
}

/// manifest.schema.json#/$defs/FileEntry
public struct ManifestFile: Codable, Hashable, Sendable {
    public var path: String
    public var sha256: String
    public var size: Int
}
