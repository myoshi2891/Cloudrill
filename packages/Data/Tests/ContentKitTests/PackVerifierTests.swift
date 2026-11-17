import CryptoKit
import Foundation
import Testing
import DomainModels
@testable import ContentKit

struct PublicKeyRingTests {
    @Test func loadsTestKeys() throws { #expect(try PackFixtures.keyRing().keyIDs == ["test-2026", "test-next"]) }
    @Test(arguments: [#"{"key":"invalid"}"#, #"{"key":"YQ=="}"#])
    func rejectsInvalidKey(json: String) { #expect(throws: (any Error).self) { try PublicKeyRing(data: Data(json.utf8)) } }
}

struct PackVerifierTests {
    @Test(arguments: [("test-alpha", "1.0.0"), ("test-alpha", "1.1.0"), ("test-beta", "1.0.0")])
    func validPacks(exam: String, version: String) throws {
        let manifest = try PackFixtures.verifier().verify(packAt: PackFixtures.valid(exam, version), expectedExamID: ExamID(rawValue: exam), currentVersion: nil)
        #expect(manifest.packVersion == version)
    }
    @Test func tamperedPacks() throws {
        struct Expected: Decodable { let directory: String; let error: String; let expectedExamID: ExamID }
        let expected = try JSONDecoder().decode([Expected].self, from: Data(contentsOf: PackFixtures.root.appending(path: "tampered/expected.json")))
        #expect(expected.count == 9)
        let verifier = try PackFixtures.verifier()
        for item in expected {
            do {
                _ = try verifier.verify(packAt: PackFixtures.root.appending(path: "tampered/\(item.directory)"), expectedExamID: item.expectedExamID, currentVersion: nil)
                Issue.record("accepted tampered pack: \(item.directory)")
            } catch {
                #expect(error.fixtureCode == item.error, "\(item.directory): \(error)")
            }
        }
    }
    @Test(arguments: ["1.0.0", "1.1.0", "1.0.0+build"])
    func notNewerIsRejected(current: String) throws {
        let verifier = try PackFixtures.verifier()
        #expect(throws: PackVerificationError.notNewer(current: current, candidate: "1.0.0")) {
            try verifier.verify(packAt: PackFixtures.valid(), expectedExamID: "test-alpha", currentVersion: SemanticVersion(current))
        }
    }
    @Test func firstInstallAllowsAnyVersion() throws {
        #expect(try PackFixtures.verifier().verify(packAt: PackFixtures.valid(), expectedExamID: "test-alpha", currentVersion: nil).packVersion == "1.0.0")
    }
    @Test(arguments: ["exam.json", "questions"])
    func symlinkIsRejected(path: String) throws {
        let root = PackFixtures.temporary()
        defer { try? FileManager.default.removeItem(at: root) }
        let pack = try PackFixtures.copy(to: root)
        let target = root.appending(path: "outside")
        try FileManager.default.moveItem(at: pack.appending(path: path), to: target)
        try FileManager.default.createSymbolicLink(at: pack.appending(path: path), withDestinationURL: target)
        let verifier = try PackFixtures.verifier()
        do {
            _ = try verifier.verify(packAt: pack, expectedExamID: "test-alpha", currentVersion: nil)
            Issue.record("accepted symlink")
        } catch {
            guard case .unsafePath = error else { Issue.record("\(error)"); return }
        }
    }
    @Test func signatureCheckedBeforeDecode() throws {
        let root = PackFixtures.temporary()
        defer { try? FileManager.default.removeItem(at: root) }
        let pack = try PackFixtures.copy(to: root)
        try Data("{".utf8).write(to: pack.appending(path: "manifest.json"))
        let verifier = try PackFixtures.verifier()
        #expect(throws: PackVerificationError.signatureInvalid) {
            try verifier.verify(packAt: pack, expectedExamID: "test-alpha", currentVersion: nil)
        }
    }
    @Test func resignedManifestStillVerifies() throws {
        // Arrange: 書き換えなしで署名し直す(以降のテストの前提の確認)
        let root = PackFixtures.temporary()
        defer { try? FileManager.default.removeItem(at: root) }
        let pack = try PackFixtures.copy(to: root)
        try resign(pack) { _ in }
        // Act / Assert
        #expect(try PackFixtures.verifier().verify(packAt: pack, expectedExamID: "test-alpha", currentVersion: nil).packVersion == "1.0.0")
    }
    @Test(arguments: PackLoader.loadedFiles)
    func unlistedLoadedFileIsRejected(path: String) throws {
        // Arrange: PackLoader が読むファイルを manifest から外し、正しく署名する
        let root = PackFixtures.temporary()
        defer { try? FileManager.default.removeItem(at: root) }
        let pack = try PackFixtures.copy(to: root)
        try resign(pack) { $0.files.removeAll { $0.path == path } }
        // Act / Assert
        let verifier = try PackFixtures.verifier()
        #expect(throws: PackVerificationError.fileMissing(path)) {
            try verifier.verify(packAt: pack, expectedExamID: "test-alpha", currentVersion: nil)
        }
    }
    @Test func modifiedUnlistedLoadedFileIsRejected() throws {
        // Arrange: manifest から外した exam.json を書き換える(ハッシュの検証を逃れる経路)
        let root = PackFixtures.temporary()
        defer { try? FileManager.default.removeItem(at: root) }
        let pack = try PackFixtures.copy(to: root)
        try resign(pack) { $0.files.removeAll { $0.path == "exam.json" } }
        try Data("{}".utf8).write(to: pack.appending(path: "exam.json"))
        // Act / Assert
        let verifier = try PackFixtures.verifier()
        #expect(throws: PackVerificationError.fileMissing("exam.json")) {
            try verifier.verify(packAt: pack, expectedExamID: "test-alpha", currentVersion: nil)
        }
    }
    @Test func extraUnlistedFileIsAccepted() throws {
        // Arrange: manifest に載っていない余分なファイル。PackLoader は読まないので許容する
        let root = PackFixtures.temporary()
        defer { try? FileManager.default.removeItem(at: root) }
        let pack = try PackFixtures.copy(to: root)
        try Data("{}".utf8).write(to: pack.appending(path: "extra.json"))
        // Act
        let manifest = try PackFixtures.verifier().verify(packAt: pack, expectedExamID: "test-alpha", currentVersion: nil)
        let reader = SpyFileReader()
        _ = try PackLoader(fileReader: reader).load(packAt: pack, manifest: manifest)
        // Assert
        #expect(!manifest.files.contains { $0.path == "extra.json" })
        #expect(!reader.paths.contains { $0.hasSuffix("extra.json") })
    }
    /// manifest を書き換え、テスト鍵で署名し直す。鍵は contentpack.testing.test_signing_key と同じ導出で、ファイルに保存しない。
    private func resign(_ pack: URL, _ edit: (inout Manifest) -> Void) throws {
        var manifest = try ContentDecoder.make().decode(Manifest.self, from: Data(contentsOf: pack.appending(path: "manifest.json")))
        edit(&manifest)
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        let raw = try encoder.encode(manifest)
        let seed = Data(SHA256.hash(data: Data("examprep-test-key:\(manifest.keyID)".utf8)))
        let key = try Curve25519.Signing.PrivateKey(rawRepresentation: seed)
        try raw.write(to: pack.appending(path: "manifest.json"))
        try key.signature(for: raw).base64EncodedData().write(to: pack.appending(path: "manifest.sig"))
    }
    @Test(arguments: ["manifest.json", "manifest.sig"])
    func missingMetadata(path: String) throws {
        let root = PackFixtures.temporary()
        defer { try? FileManager.default.removeItem(at: root) }
        let pack = try PackFixtures.copy(to: root)
        try FileManager.default.removeItem(at: pack.appending(path: path))
        let verifier = try PackFixtures.verifier()
        #expect(throws: path == "manifest.json" ? PackVerificationError.manifestMissing : .signatureMissing) {
            try verifier.verify(packAt: pack, expectedExamID: "test-alpha", currentVersion: nil)
        }
    }
}

extension PackVerificationError {
    var fixtureCode: String {
        switch self {
        case .manifestMissing: "manifest_missing"
        case .signatureMissing: "signature_missing"
        case .signatureInvalid: "signature_invalid"
        case .manifestUndecodable: "manifest_undecodable"
        case .unsupportedFormat: "unsupported_format"
        case .appTooOld: "app_too_old"
        case .examMismatch: "exam_mismatch"
        case .notNewer: "not_newer"
        case .unsafePath: "unsafe_path"
        case .fileMissing: "file_missing"
        case .sizeMismatch: "size_mismatch"
        case .hashMismatch: "hash_mismatch"
        }
    }
}
