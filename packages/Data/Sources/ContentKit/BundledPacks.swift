import Foundation
import DomainModels
import DomainInterfaces

/// アプリバンドルの Packs/。カタログに記録された同梱版を使い、配信カタログの最新版とは区別する。
public struct BundledPacks: Sendable {
    public let root: URL
    public let catalog: Catalog

    public init(root: URL, catalog: Catalog) {
        self.root = root.standardizedFileURL
        self.catalog = catalog
    }

    public init(root: URL) throws(ContentError) {
        self.init(root: root, catalog: try PackFiles(root: root, reader: FileManagerReader()).decode(Catalog.self, "catalog.json"))
    }

    func location(for examID: ExamID) throws(ContentError) -> PackLocation? {
        guard let version = catalog.exams.first(where: { $0.id == examID })?.latestPackVersion else { return nil }
        guard SemanticVersion(version) != nil,
              examID.rawValue.range(of: #"\A[a-z0-9]+(?:-[a-z0-9]+)*\z"#, options: .regularExpression) != nil else {
            throw .storage("invalid bundled pack location")
        }
        let directory = root.appending(path: "\(examID.rawValue)/\(version)")
        guard (try? directory.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) == true else { return nil }
        return PackLocation(source: .bundled, version: version)
    }
}
