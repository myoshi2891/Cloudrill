import Foundation
import DomainModels
import DomainInterfaces

public protocol FileReading: Sendable { func read(_ url: URL) throws -> Data }
public struct FileManagerReader: FileReading {
    public init() {}
    public func read(_ url: URL) throws -> Data { try Data(contentsOf: url) }
}

/// I/O の失敗とデコードの失敗を区別する。インスタンスを本文キャッシュと共有する。
struct PackFiles: Sendable {
    let root: URL
    let reader: any FileReading
    /// manifest に載っているパス。nil は manifest を読む前(manifest.json・カタログ)で、制限しない。
    /// 載っていないファイルはハッシュの検証を受けていないので、遅延読み込みでも読まない。
    var listed: Set<String>? = nil
    func data(_ path: String) throws(ContentError) -> Data {
        let url = root.appending(path: path).standardizedFileURL
        guard !path.hasPrefix("/"), !path.split(separator: "/").contains(".."),
              url.path.hasPrefix(root.standardizedFileURL.path + "/") else { throw .storage("unsafe path: \(path)") }
        if let listed, !listed.contains(path) { throw .fileMissing(path) }
        // 同梱パックは起動時に署名を再検証しないので、読み込みのたびにパック内のシンボリックリンクを拒否する。
        var component = root
        for part in path.split(separator: "/") {
            component.append(path: String(part))
            if (try? component.resourceValues(forKeys: [.isSymbolicLinkKey]).isSymbolicLink) == true {
                throw .storage("unsafe path: \(path)")
            }
        }
        do { return try reader.read(url) }
        catch { throw .fileMissing(path) }
    }
    func decode<T: Decodable>(_ type: T.Type, _ path: String) throws(ContentError) -> T {
        let raw = try data(path)
        do { return try ContentDecoder.make().decode(type, from: raw) }
        catch { throw .undecodable(path: path, reason: String(describing: error)) }
    }
}

