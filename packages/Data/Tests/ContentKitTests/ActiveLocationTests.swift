import Foundation
import Testing
import DomainModels
@testable import ContentKit

struct ActiveLocationTests {
    struct Scenario: Sendable {
        let bundledVersion: String?
        let installedVersion: String?
        let expectedSource: PackSource?

        init(_ bundled: String?, _ installed: String?, _ expected: PackSource?) {
            bundledVersion = bundled
            installedVersion = installed
            expectedSource = expected
        }

        var bundled: PackLocation? { bundledVersion.map { .init(source: .bundled, version: $0) } }
        var installed: PackLocation? { installedVersion.map { .init(source: .installed, version: $0) } }
        var expected: PackLocation? {
            switch expectedSource {
            case .bundled: bundled
            case .installed: installed
            case nil: nil
            }
        }
    }

    static let scenarios: [Scenario] = [
        .init(nil, nil, nil),
        .init("1.0.0", nil, .bundled),
        .init(nil, "1.0.0", .installed),
        .init("1.0.0", "1.0.0", .installed),
        .init("2.0.0", "1.9.9", .bundled),
        .init("1.9.9", "2.0.0", .installed),
        .init("1.10.0", "1.9.0", .bundled),
        .init("1.9.0", "1.10.0", .installed),
        .init("1.0.10", "1.0.9", .bundled),
        .init("1.0.9", "1.0.10", .installed),
        .init("1.0.0", "1.0.0-rc.1", .bundled),
        .init("1.0.0-rc.1", "1.0.0", .installed),
        .init("1.0.0-beta.11", "1.0.0-beta.2", .bundled),
        .init("1.0.0-beta.2", "1.0.0-beta.11", .installed),
        .init("1.0.0+bundle", "1.0.0+installed", .installed),
        .init("1.0.0+bundle", "1.0.0", .installed),
        .init("1.0.0", "1.0.0+installed", .installed),
    ]

    // 版の選択はディレクトリの存在だけを調べ、パックの本文を読まず、状態も変更しない。
    @Test(arguments: scenarios)
    func serviceSelectsVersion(scenario: Scenario) async throws {
        let root = PackFixtures.temporary()
        defer { try? FileManager.default.removeItem(at: root) }
        let bundledRoot = root.appending(path: "Packs")
        let storeRoot = root.appending(path: "Content")
        let store = PackStore(root: storeRoot)
        var catalog = try CatalogFixtures.catalog()
        catalog.exams[0].latestPackVersion = scenario.bundledVersion
        if let location = scenario.bundled {
            try FileManager.default.createDirectory(
                at: bundledRoot.appending(path: "test-alpha/\(location.version)"),
                withIntermediateDirectories: true
            )
        }
        if let location = scenario.installed {
            try FileManager.default.createDirectory(
                at: storeRoot.appending(path: "test-alpha/versions/\(location.version)"),
                withIntermediateDirectories: true
            )
            try await store.activate(location, for: "test-alpha")
        }
        let before = try await store.state(for: "test-alpha")
        let service = ExamCatalogService(
            bundled: BundledPacks(root: bundledRoot, catalog: catalog), store: store, cachedCatalog: nil
        )
        #expect(try await service.activeLocation(for: "test-alpha") == scenario.expected)
        #expect(try await store.state(for: "test-alpha") == before)
    }

    @Test func missingInstalledDirectoryFallsBackToBundle() async throws {
        let root = PackFixtures.temporary()
        defer { try? FileManager.default.removeItem(at: root) }
        let store = PackStore(root: root)
        try await CatalogFixtures.install(store, root: root, version: "1.1.0")
        try FileManager.default.removeItem(at: root.appending(path: "test-alpha/versions/1.1.0"))
        let before = try await store.state(for: "test-alpha")
        let service = try ExamCatalogService(bundled: CatalogFixtures.bundled(), store: store, cachedCatalog: nil)
        #expect(try await service.activeLocation(for: "test-alpha") == .init(source: .bundled, version: "1.0.0"))
        #expect(try await store.state(for: "test-alpha") == before)
    }
}
