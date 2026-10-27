import Foundation
import Testing
import DomainModels
import DomainInterfaces
@testable import ContentKit

enum CatalogFixtures {
    static func catalog(alphaVersion: String = "1.0.0") throws -> Catalog {
        var catalog = try ContentDecoder.make().decode(Catalog.self, from: Data(contentsOf: PackFixtures.root.appending(path: "catalog.json")))
        catalog.exams[0].latestPackVersion = alphaVersion
        return catalog
    }
    static func bundled(catalog: Catalog? = nil) throws -> BundledPacks {
        try BundledPacks(root: PackFixtures.root.appending(path: "valid"), catalog: catalog ?? self.catalog())
    }
    static func install(_ store: PackStore, root: URL, version: String, exam: ExamID = "test-alpha") async throws {
        let staged = root.appending(path: "\(exam.rawValue)/staging/\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: staged.deletingLastPathComponent(), withIntermediateDirectories: true)
        try FileManager.default.copyItem(at: PackFixtures.valid(exam.rawValue, version), to: staged)
        try await store.install(staged: staged, version: version, for: exam)
        try await store.activate(.init(source: .installed, version: version), for: exam)
    }
}

struct ExamCatalogServiceTests {
    @Test func bundledPacksAreListed() async throws {
        let root = PackFixtures.temporary()
        let service = try ExamCatalogService(bundled: CatalogFixtures.bundled(), store: PackStore(root: root), cachedCatalog: nil)
        let entries = try await service.entries()
        #expect(entries.map(\.id) == ["test-alpha", "test-beta"])
        #expect(entries.allSatisfy { $0.isAvailable && $0.isInstalled })
        #expect(entries.map(\.entry.status) == [.available, .available])
        #expect(!FileManager.default.fileExists(atPath: root.path))
    }

    @Test func firstLaunchUsesBundledWithoutCopy() async throws {
        let root = PackFixtures.temporary()
        let service = try ExamCatalogService(bundled: CatalogFixtures.bundled(), store: PackStore(root: root), cachedCatalog: nil)
        #expect(try await service.activeLocation(for: "test-alpha") == .init(source: .bundled, version: "1.0.0"))
        #expect(!FileManager.default.fileExists(atPath: root.path))
    }

    @Test func newerInstalledWins() async throws {
        let root = PackFixtures.temporary()
        defer { try? FileManager.default.removeItem(at: root) }
        let store = PackStore(root: root)
        try await CatalogFixtures.install(store, root: root, version: "1.1.0")
        let service = try ExamCatalogService(bundled: CatalogFixtures.bundled(), store: store, cachedCatalog: nil)
        #expect(try await service.activeLocation(for: "test-alpha") == .init(source: .installed, version: "1.1.0"))
    }

    @Test func newerBundledWinsAfterAppUpdate() async throws {
        let root = PackFixtures.temporary()
        defer { try? FileManager.default.removeItem(at: root) }
        let store = PackStore(root: root)
        try await CatalogFixtures.install(store, root: root, version: "1.0.0")
        let service = try ExamCatalogService(bundled: CatalogFixtures.bundled(catalog: CatalogFixtures.catalog(alphaVersion: "1.1.0")), store: store, cachedCatalog: nil)
        #expect(try await service.activeLocation(for: "test-alpha") == .init(source: .bundled, version: "1.1.0"))
        // 選択は読み取りだけ。整合チェックに成功した後で bootstrap が有効化する。
        #expect(try await store.state(for: "test-alpha").current == .init(source: .installed, version: "1.0.0"))
    }

    @Test func cachedCatalogDoesNotChangeBundledVersion() async throws {
        let root = PackFixtures.temporary()
        var cached = try CatalogFixtures.catalog(alphaVersion: "99.0.0")
        cached.generatedAt += 60
        let service = try ExamCatalogService(bundled: CatalogFixtures.bundled(), store: PackStore(root: root), cachedCatalog: cached)
        #expect(try await service.entries().first?.entry.latestPackVersion == "99.0.0")
        #expect(try await service.activeLocation(for: "test-alpha")?.version == "1.0.0")
    }

    @Test func comingSoonIsListedButNotAvailable() async throws {
        var catalog = try CatalogFixtures.catalog()
        catalog.exams[0].status = .comingSoon
        catalog.exams[0].latestPackVersion = nil
        catalog.exams[0].minAppVersion = nil
        let service = try ExamCatalogService(bundled: CatalogFixtures.bundled(catalog: catalog), store: PackStore(root: PackFixtures.temporary()), cachedCatalog: nil)
        let entry = try #require(await service.entries().first)
        #expect(entry.id == "test-alpha" && !entry.isAvailable && !entry.isInstalled)
        #expect(try await service.activeLocation(for: "test-alpha") == nil)
    }

    @Test func retiredHiddenUnlessInstalled() async throws {
        let root = PackFixtures.temporary()
        defer { try? FileManager.default.removeItem(at: root) }
        let store = PackStore(root: root)
        try await CatalogFixtures.install(store, root: root, version: "1.0.0")
        var catalog = try CatalogFixtures.catalog()
        for index in catalog.exams.indices { catalog.exams[index].status = .retired }
        let bundled = BundledPacks(root: root.appending(path: "empty-bundle"), catalog: catalog)
        let service = ExamCatalogService(bundled: bundled, store: store, cachedCatalog: nil)
        let entries = try await service.entries()
        #expect(entries.map(\.id) == ["test-alpha"])
        #expect(entries.first?.isAvailable == true)
        #expect(try await service.activeLocation(for: "test-beta") == nil)
    }

    @Test func brokenStateIsIsolatedPerEntry() async throws {
        let root = PackFixtures.temporary()
        defer { try? FileManager.default.removeItem(at: root) }
        try FileManager.default.createDirectory(at: root.appending(path: "test-alpha"), withIntermediateDirectories: true)
        try Data("{".utf8).write(to: root.appending(path: "test-alpha/state.json"))
        let service = try ExamCatalogService(bundled: CatalogFixtures.bundled(), store: PackStore(root: root), cachedCatalog: nil)
        let entries = try await service.entries()
        #expect(entries.map(\.id) == ["test-alpha", "test-beta"])
        #expect(entries[0].failure != nil && !entries[0].isInstalled)
        #expect(entries[1].failure == nil && entries[1].isAvailable)
    }

    @Test func staleBundledStateUsesActualBundle() async throws {
        let root = PackFixtures.temporary()
        defer { try? FileManager.default.removeItem(at: root) }
        let store = PackStore(root: root)
        try await store.activate(.init(source: .bundled, version: "0.9.0"), for: "test-alpha")
        let service = try ExamCatalogService(bundled: CatalogFixtures.bundled(), store: store, cachedCatalog: nil)
        #expect(try await service.activeLocation(for: "test-alpha") == .init(source: .bundled, version: "1.0.0"))
        #expect(try await service.activeLocation(for: "unknown-exam") == nil)
    }

    @Test func readsCatalogFromBundleRoot() throws {
        let bundled = try BundledPacks(root: PackFixtures.root)
        #expect(bundled.catalog.exams.map(\.id) == ["test-alpha", "test-beta"])
        #expect(throws: ContentError.fileMissing("catalog.json")) { try BundledPacks(root: PackFixtures.temporary()) }
    }
}
