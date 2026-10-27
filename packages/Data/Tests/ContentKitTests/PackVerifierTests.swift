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
