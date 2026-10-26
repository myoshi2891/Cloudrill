import CryptoKit
import Foundation
import DomainModels

public enum PackVerificationError: Error, Equatable, Sendable {
    case manifestMissing, signatureMissing, signatureInvalid, manifestUndecodable
    case unsupportedFormat(Int)
    case appTooOld(required: String)
    case examMismatch(expected: ExamID, actual: ExamID)
    case notNewer(current: String, candidate: String)
    case unsafePath(String), fileMissing(String), sizeMismatch(String), hashMismatch(String)
}

public struct PackVerifier: Sendable {
    private let keyRing: PublicKeyRing
    private let appVersion: SemanticVersion
    private let supportedFormatVersion: Int

    public init(keyRing: PublicKeyRing, appVersion: SemanticVersion, supportedFormatVersion: Int) {
        self.keyRing = keyRing
        self.appVersion = appVersion
        self.supportedFormatVersion = supportedFormatVersion
    }

    public func verify(packAt directory: URL, expectedExamID: ExamID, currentVersion: SemanticVersion?) throws(PackVerificationError) -> Manifest {
        let (raw, verifiedIDs) = try checkSignature(directory)
        let manifest: Manifest
        do { manifest = try ContentDecoder.make().decode(Manifest.self, from: raw) }
        catch { throw .manifestUndecodable }
        guard verifiedIDs.contains(manifest.keyID) else { throw .signatureInvalid }
        try checkVersions(manifest, expected: expectedExamID, current: currentVersion)
        try checkFiles(manifest, directory: directory)
        return manifest
    }

    private func checkSignature(_ directory: URL) throws(PackVerificationError) -> (Data, Set<String>) {
        guard let raw = try? Data(contentsOf: directory.appending(path: "manifest.json")) else { throw .manifestMissing }
        guard let encoded = try? Data(contentsOf: directory.appending(path: "manifest.sig")) else { throw .signatureMissing }
        guard let signature = Data(base64Encoded: encoded), signature.count == 64,
              signature.base64EncodedData() == encoded else { throw .signatureInvalid }
        let verifiedIDs = Set(keyRing.keys.filter { $0.value.isValidSignature(signature, for: raw) }.keys)
        guard !verifiedIDs.isEmpty else { throw .signatureInvalid }
        return (raw, verifiedIDs)
    }

    private func checkVersions(_ manifest: Manifest, expected: ExamID, current: SemanticVersion?) throws(PackVerificationError) {
        guard let candidate = SemanticVersion(manifest.packVersion), let minimum = SemanticVersion(manifest.minAppVersion),
              manifest.formatVersion >= 1, !manifest.files.isEmpty else { throw .manifestUndecodable }
        guard manifest.formatVersion <= supportedFormatVersion else { throw .unsupportedFormat(manifest.formatVersion) }
        guard appVersion >= minimum else { throw .appTooOld(required: manifest.minAppVersion) }
        guard manifest.examID == expected else { throw .examMismatch(expected: expected, actual: manifest.examID) }
        if let current, candidate <= current { throw .notNewer(current: current.description, candidate: manifest.packVersion) }
    }

    private func checkFiles(_ manifest: Manifest, directory: URL) throws(PackVerificationError) {
        let root = directory.standardizedFileURL
        for entry in manifest.files {
            let relative = entry.path
            let file = try checkPath(relative, root: root)
            guard entry.size >= 0, entry.sha256.range(of: #"\A[0-9a-f]{64}\z"#, options: .regularExpression) != nil else {
                throw .manifestUndecodable
            }
            guard let values = try? file.resourceValues(forKeys: [.isRegularFileKey, .fileSizeKey]), values.isRegularFile == true else {
                throw .fileMissing(relative)
            }
            guard values.fileSize == entry.size else { throw .sizeMismatch(relative) }
            let digest: String
            do {
                let handle = try FileHandle(forReadingFrom: file)
                defer { try? handle.close() }
                var hash = SHA256()
                while let chunk = try handle.read(upToCount: 1024 * 1024), !chunk.isEmpty { hash.update(data: chunk) }
                digest = hash.finalize().map { String(format: "%02x", $0) }.joined()
            } catch { throw .fileMissing(relative) }
            guard digest == entry.sha256 else { throw .hashMismatch(relative) }
        }
    }
    private func checkPath(_ relative: String, root: URL) throws(PackVerificationError) -> URL {
    // manifest.schema.json と同じ相対パスの規則。
    guard relative.range(of: #"\A(?!/)(?!(?:.*/)?\.\.(?:/|$))[A-Za-z0-9._/-]+\z"#, options: .regularExpression) != nil else {
        throw .unsafePath(relative)
    }
    let file = root.appending(path: relative).standardizedFileURL
    guard file.path.hasPrefix(root.path + "/") else { throw .unsafePath(relative) }
    var component = root
    for part in relative.split(separator: "/") {
        component.append(path: String(part))
        if (try? component.resourceValues(forKeys: [.isSymbolicLinkKey]).isSymbolicLink) == true {
            throw .unsafePath(relative)
        }
    }
    guard file.resolvingSymlinksInPath().path.hasPrefix(root.resolvingSymlinksInPath().path + "/") else {
        throw .unsafePath(relative)
    }
        return file
    }

}
