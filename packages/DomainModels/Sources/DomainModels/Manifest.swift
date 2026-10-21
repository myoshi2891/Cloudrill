import Foundation

/// manifest.schema.json。`createdAt` のデコードには `ContentDecoder.make()`(ISO 8601)を使う。
/// 署名は manifest.json のバイト列に対して別ファイル manifest.sig に置く(DDD C-06)。
public struct Manifest: Codable, Hashable, Sendable {
    /// パックの構造の版。アプリが解釈できない版は取り込まない(DDD X-05)
    public var formatVersion: Int
    /// P0-S09 で `ExamID` 型に置き換える
    public var examID: String
    /// 署名に使った鍵の ID(鍵のローテーション用)
    public var keyID: String
    public var packVersion: String
    public var examGuideVersion: String
    public var minAppVersion: String
    public var createdAt: Date
    public var files: [ManifestFile]
}

/// manifest.schema.json#/$defs/FileEntry
public struct ManifestFile: Codable, Hashable, Sendable {
    public var path: String
    public var sha256: String
    public var size: Int
}
