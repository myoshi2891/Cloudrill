import Foundation
import Synchronization
import Testing
@testable import ContentKit

struct FileManagerReaderTests {
    @Test func readsRegularFileAndRefusesFinalSymlink() throws {
        // Arrange
        let directory = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let target = directory.appending(path: "target.json")
        try Data("{}".utf8).write(to: target)
        let link = directory.appending(path: "link.json")
        try FileManager.default.createSymbolicLink(at: link, withDestinationURL: target)
        let reader = FileManagerReader()
        // Act / Assert
        #expect(try reader.read(target) == Data("{}".utf8))
        #expect(throws: POSIXError.self) { try reader.read(link) }
    }

    @Test func refusesNonRegularFilesWithoutBlocking() throws {
        // Arrange: 書き手のいない FIFO(ブロックする開き方なら open で止まる)とディレクトリ
        let directory = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let fifo = directory.appending(path: "fifo.json")
        try #require(mkfifo(fifo.path, 0o600) == 0)
        let reader = FileManagerReader()
        // Act: ブロックしてもテストが止まらないよう、別スレッドで読み、期限を設ける
        let box = ResultBox()
        let done = DispatchSemaphore(value: 0)
        Thread {
            box.set(Result { try reader.read(fifo) })
            done.signal()
        }.start()
        guard done.wait(timeout: .now() + 5) == .success else {
            Issue.record("FIFO の読み込みが 5 秒以内に終わらなかった(ブロックする開き方になっている)")
            // 読み手が open で止まっているので、書き手として開いて解放する
            let writer = open(fifo.path, O_WRONLY | O_NONBLOCK)
            if writer >= 0 { close(writer) }
            return
        }
        // Assert
        #expect(throws: POSIXError(.EFTYPE)) { try box.get() }
        #expect(throws: POSIXError(.EFTYPE)) { try reader.read(directory) }
    }
}

private final class ResultBox: Sendable {
    private let result = Mutex<Result<Data, any Error>?>(nil)
    func set(_ value: Result<Data, any Error>) { result.withLock { $0 = value } }
    func get() throws -> Data {
        guard let value = result.withLock({ $0 }) else { throw POSIXError(.EIO) }
        return try value.get()
    }
}
