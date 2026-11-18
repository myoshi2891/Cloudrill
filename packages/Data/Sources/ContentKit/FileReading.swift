import Foundation
import DomainModels
import DomainInterfaces

public protocol FileReading: Sendable { func read(_ url: URL) throws -> Data }
public struct FileManagerReader: FileReading {
    public init() {}
    /// 最後の要素を O_NOFOLLOW で開き、その記述子から読む。PackFiles の確認と読み込みのあいだに
    /// ファイルをシンボリックリンクへ差し替えられても、リンク先を読まない(途中のディレクトリの差し替えは対象外)。
    /// FIFO やデバイスを開いて待ち続けないよう O_NONBLOCK で開き、同じ記述子の fstat で通常のファイルだけを読む。
    public func read(_ url: URL) throws -> Data {
        let descriptor = open(url.path, O_RDONLY | O_NOFOLLOW | O_NONBLOCK | O_CLOEXEC)
        guard descriptor >= 0 else { throw POSIXError(POSIXErrorCode(rawValue: errno) ?? .EIO) }
        var status = stat()
        guard fstat(descriptor, &status) == 0 else {
            let code = POSIXErrorCode(rawValue: errno) ?? .EIO
            close(descriptor)
            throw POSIXError(code)
        }
        guard status.st_mode & S_IFMT == S_IFREG else {
            close(descriptor)
            throw POSIXError(.EFTYPE)
        }
        let handle = FileHandle(fileDescriptor: descriptor, closeOnDealloc: true)
        return try handle.readToEnd() ?? Data()
    }
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

