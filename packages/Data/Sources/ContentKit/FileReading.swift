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
    func data(_ path: String) throws(ContentError) -> Data {
        let url = root.appending(path: path).standardizedFileURL
        guard !path.hasPrefix("/"), !path.split(separator: "/").contains(".."),
              url.path.hasPrefix(root.standardizedFileURL.path + "/") else { throw .storage("unsafe path: \(path)") }
        do { return try reader.read(url) }
        catch { throw .fileMissing(path) }
    }
    func decode<T: Decodable>(_ type: T.Type, _ path: String) throws(ContentError) -> T {
        let raw = try data(path)
        do { return try ContentDecoder.make().decode(type, from: raw) }
        catch { throw .undecodable(path: path, reason: String(describing: error)) }
    }
}

