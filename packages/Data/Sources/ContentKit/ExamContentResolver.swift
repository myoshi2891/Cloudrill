import Foundation
import DomainModels
import DomainInterfaces

public struct ExamContentResolver: ExamContentResolving {
    private let bundled: BundledPacks
    private let store: PackStore
    private let checker: ContentIntegrityChecker

    public init(bundled: BundledPacks, store: PackStore, supportedKinds: Set<QuestionKind>) {
        self.bundled = bundled; self.store = store
        checker = ContentIntegrityChecker(supportedKinds: supportedKinds)
    }

    public func content(for examID: ExamID, version: String) async throws(ContentError) -> any ExamContentProvider {
        let installed = try await store.directory(for: .init(source: .installed, version: version),
            examID: examID, bundledRoot: bundled.root)
        let directory: URL
        if FileManager.default.fileExists(atPath: installed.path) {
            directory = installed
        } else {
            directory = try await store.directory(for: .init(source: .bundled, version: version),
                examID: examID, bundledRoot: bundled.root)
        }
        let loader = PackLoader()
        let manifest = try loader.manifest(packAt: directory)
        guard manifest.examID == examID, manifest.packVersion == version else {
            throw .storage("pack manifest identity mismatch")
        }
        let content = try loader.load(packAt: directory, manifest: manifest)
        guard content.definition.id == examID, content.vendor.id == content.definition.vendor else {
            throw .storage("pack content identity mismatch")
        }
        let violations = checker.check(content)
        guard violations.isEmpty else { throw .integrityViolations(violations) }
        return content
    }
}
