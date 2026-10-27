import Foundation
import DomainModels
@testable import ContentKit

/// Python が生成した契約 fixture をコピーせず直接読む。
enum PackFixtures {
    static let root = URL(filePath: #filePath)
        .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
        .appending(path: "../../content/tests/fixtures/packs").standardized
    static func valid(_ exam: String = "test-alpha", _ version: String = "1.0.0") -> URL {
        root.appending(path: "valid/\(exam)/\(version)")
    }
    static func keyRing() throws -> PublicKeyRing {
        try PublicKeyRing(data: Data(contentsOf: root.appending(path: "test-keys.json")))
    }
    static func verifier() throws -> PackVerifier {
        try PackVerifier(keyRing: keyRing(), appVersion: SemanticVersion("1.0.0")!, supportedFormatVersion: 1)
    }
    static func copy(to root: URL) throws -> URL {
        let pack = root.appending(path: "pack")
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        try FileManager.default.copyItem(at: valid(), to: pack)
        return pack
    }
    static func temporary() -> URL { FileManager.default.temporaryDirectory.appending(path: UUID().uuidString) }
}
