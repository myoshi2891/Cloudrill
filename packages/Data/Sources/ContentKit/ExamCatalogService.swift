import Foundation
import DomainModels
import DomainInterfaces

public struct ExamCatalogItem: Sendable, Identifiable {
    public let entry: CatalogEntry
    public let activeLocation: PackLocation?
    public var id: ExamID { entry.id }
    /// 同梱パックも取得済みとして扱う。
    public var isInstalled: Bool { activeLocation != nil }
    public var isAvailable: Bool { entry.status != .comingSoon && isInstalled }
}

public struct ExamCatalogService: Sendable {
    let bundled: BundledPacks
    let store: PackStore
    private let cachedCatalog: Catalog?

    public init(bundled: BundledPacks, store: PackStore, cachedCatalog: Catalog?) {
        self.bundled = bundled
        self.store = store
        self.cachedCatalog = cachedCatalog
    }

    var catalogEntries: [CatalogEntry] {
        guard let cachedCatalog, cachedCatalog.generatedAt >= bundled.catalog.generatedAt else { return bundled.catalog.exams }
        // キャッシュにない同梱試験もオフラインで利用できるように残す。
        let cachedIDs = Set(cachedCatalog.exams.map(\.id))
        return cachedCatalog.exams + bundled.catalog.exams.filter { !cachedIDs.contains($0.id) }
    }

    public func entries() async throws(ContentError) -> [ExamCatalogItem] {
        var items: [ExamCatalogItem] = []
        for entry in catalogEntries {
            let location = try await localLocation(for: entry.id)
            guard entry.status != .retired || location != nil else { continue }
            items.append(ExamCatalogItem(entry: entry, activeLocation: location))
        }
        return items
    }

    /// 状態は変更しない。選択したパックの読み込み・整合確認後に有効化する。
    public func activeLocation(for examID: ExamID) async throws(ContentError) -> PackLocation? {
        guard let entry = catalogEntries.first(where: { $0.id == examID }), entry.status != .comingSoon else { return nil }
        return try await localLocation(for: examID)
    }

    /// 起動時の読み込み。検証済みの installed とアプリ同梱のパックだけを扱う。
    /// 内容の整合確認に成功するまでは、現在の版と previous を変更しない。
    public func load(
        for examID: ExamID,
        loader: PackLoader = PackLoader(),
        integrityChecker: ContentIntegrityChecker
    ) async throws(ContentError) -> PackContent {
        guard let location = try await activeLocation(for: examID) else { throw .storage("not available") }
        let directory = try await store.directory(for: location, examID: examID, bundledRoot: bundled.root)
        let manifest = try loader.manifest(packAt: directory)
        guard manifest.examID == examID, manifest.packVersion == location.version else {
            throw .storage("pack manifest identity mismatch")
        }
        let content = try loader.load(packAt: directory, manifest: manifest)
        guard content.definition.id == examID, content.vendor.id == content.definition.vendor else {
            throw .storage("pack content identity mismatch")
        }
        let violations = integrityChecker.check(content)
        guard violations.isEmpty else { throw .integrityViolations(violations) }
        try await store.activate(location, for: examID)
        return content
    }

    private func localLocation(for examID: ExamID) async throws(ContentError) -> PackLocation? {
        let bundledLocation = try bundled.location(for: examID)
        let current = try await store.state(for: examID).current
        // 旧アプリの bundled 状態は、現在のバンドルに存在する版で置き換える。
        guard let current, current.source == .installed else { return bundledLocation }
        let directory = try await store.directory(for: current, examID: examID, bundledRoot: bundled.root)
        guard (try? directory.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) == true else { return bundledLocation }
        if let bundledLocation,
           let bundledVersion = SemanticVersion(bundledLocation.version),
           let installedVersion = SemanticVersion(current.version), bundledVersion > installedVersion {
            return bundledLocation
        }
        return current
    }
}
