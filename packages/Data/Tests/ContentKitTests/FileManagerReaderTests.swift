import Foundation
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
}
