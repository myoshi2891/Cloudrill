import Foundation
import Testing
import DomainModels
import DomainInterfaces
@testable import ContentKit

struct ContentBootstrapperTests {
    private let checker = ContentIntegrityChecker(supportedKinds: [.single, .multiple])

    private func bootstrapper(_ bundled: BundledPacks, store: PackStore, reader: any FileReading = FileManagerReader()) -> ContentBootstrapper {
        ContentBootstrapper(catalogService: ExamCatalogService(bundled: bundled, store: store, cachedCatalog: nil),
                            loader: PackLoader(fileReader: reader), integrityChecker: checker)
    }
    private func copiedBundle(_ root: URL, alphaVersion: String = "1.0.0") throws -> BundledPacks {
        let bundle = root.appending(path: "bundle")
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        try FileManager.default.copyItem(at: PackFixtures.root.appending(path: "valid"), to: bundle)
        return try BundledPacks(root: bundle, catalog: CatalogFixtures.catalog(alphaVersion: alphaVersion))
    }
    private func breakIntegrity(_ directory: URL) throws {
        let path = directory.appending(path: "questions/index.json")
        var index = try ContentDecoder.make().decode([QuestionIndexEntry].self, from: Data(contentsOf: path))
        index[0].domain = 9
        try JSONEncoder().encode(index).write(to: path)
    }

    @Test func firstLaunchActivatesBundledWithoutCopyOrBodyReads() async throws {
        let root = PackFixtures.temporary()
        defer { try? FileManager.default.removeItem(at: root) }
        let store = PackStore(root: root)
        let spy = SpyFileReader()
        let result = await bootstrapper(try CatalogFixtures.bundled(), store: store, reader: spy).bootstrap()
        #expect(Set(result.available.keys) == ["test-alpha", "test-beta"])
        #expect(result.failures.isEmpty && result.fatalError == nil)
        #expect(result.available["test-alpha"]?.packVersion == "1.0.0")
        #expect(try await store.state(for: "test-alpha").current == .init(source: .bundled, version: "1.0.0"))
        #expect(!FileManager.default.fileExists(atPath: root.appending(path: "test-alpha/versions").path))
        #expect(!spy.paths.contains { $0.contains("questions/domain") || $0.hasSuffix("manifest.sig") })
        #expect(spy.paths.count == 12) // 各試験の manifest と起動時の5ファイル。
        let beta = try #require(result.available["test-beta"])
        await #expect(throws: ContentError.featureDisabled("caseStudies")) { try await beta.caseStudies() }
    }

    @Test func newerBundledActivationKeepsInstalledAsPrevious() async throws {
        let root = PackFixtures.temporary()
        defer { try? FileManager.default.removeItem(at: root) }
        let store = PackStore(root: root)
        try await CatalogFixtures.install(store, root: root, version: "1.0.0")
        let bundled = try CatalogFixtures.bundled(catalog: CatalogFixtures.catalog(alphaVersion: "1.1.0"))
        let bootstrap = bootstrapper(bundled, store: store)
        let result = await bootstrap.bootstrap()
        #expect(result.available["test-alpha"]?.packVersion == "1.1.0")
        let state = try await store.state(for: "test-alpha")
        #expect(state.current == .init(source: .bundled, version: "1.1.0"))
        #expect(state.previous == .init(source: .installed, version: "1.0.0"))
        _ = await bootstrap.bootstrap()
        #expect(try await store.state(for: "test-alpha") == state)
    }

    @Test func installedPackLoadsWithoutFullReverification() async throws {
        let root = PackFixtures.temporary()
        defer { try? FileManager.default.removeItem(at: root) }
        let store = PackStore(root: root)
        try await CatalogFixtures.install(store, root: root, version: "1.1.0")
        let spy = SpyFileReader()
        let result = await bootstrapper(try CatalogFixtures.bundled(), store: store, reader: spy).bootstrap()
        #expect(result.available["test-alpha"]?.packVersion == "1.1.0")
        #expect(spy.paths.contains { $0.hasSuffix("test-alpha/versions/1.1.0/exam.json") })
        #expect(!spy.paths.contains { $0.hasSuffix("manifest.sig") || $0.contains("questions/domain") })
    }

    @Test func comingSoonIsNotLoadable() async throws {
        var catalog = try CatalogFixtures.catalog()
        catalog.exams[0].status = .comingSoon
        let root = PackFixtures.temporary()
        defer { try? FileManager.default.removeItem(at: root) }
        let service = try ExamCatalogService(bundled: CatalogFixtures.bundled(catalog: catalog), store: PackStore(root: root), cachedCatalog: nil)
        await #expect(throws: ContentError.storage("not available")) { try await service.load(for: "test-alpha", integrityChecker: checker) }
        await #expect(throws: ContentError.storage("not available")) { try await service.load(for: "unknown-exam", integrityChecker: checker) }
        let result = await ContentBootstrapper(catalogService: service, integrityChecker: checker).bootstrap()
        #expect(Set(result.available.keys) == ["test-beta"])
        #expect(result.failures.isEmpty && result.fatalError == nil)
    }

    @Test func bootstrapVerifiesIntegrityAndPreservesPreviousStateOnFailure() async throws {
        let root = PackFixtures.temporary()
        defer { try? FileManager.default.removeItem(at: root) }
        let bundled = try copiedBundle(root, alphaVersion: "1.1.0")
        try breakIntegrity(bundled.root.appending(path: "test-alpha/1.1.0"))
        let storeRoot = root.appending(path: "store")
        let store = PackStore(root: storeRoot)
        try await CatalogFixtures.install(store, root: storeRoot, version: "1.0.0")
        let before = try await store.state(for: "test-alpha")
        let result = await bootstrapper(bundled, store: store).bootstrap()
        #expect(Set(result.available.keys) == ["test-beta"])
        guard case .integrityViolations(let violations) = result.failures["test-alpha"] else {
            Issue.record("expected integrity violations"); return
        }
        #expect(violations.contains { if case .unknownDomain(questionID: _, domain: 9) = $0 { true } else { false } })
        #expect(result.fatalError == nil)
        #expect(try await store.state(for: "test-alpha") == before)
    }

    @Test func bootstrapFailsWhenNoUsableExam() async throws {
        let root = PackFixtures.temporary()
        defer { try? FileManager.default.removeItem(at: root) }
        let bundled = try copiedBundle(root)
        for exam in ["test-alpha", "test-beta"] {
            try FileManager.default.removeItem(at: bundled.root.appending(path: "\(exam)/1.0.0/exam.json"))
        }
        let result = await bootstrapper(bundled, store: PackStore(root: root.appending(path: "store"))).bootstrap()
        #expect(result.available.isEmpty)
        #expect(result.failures == ["test-alpha": .fileMissing("exam.json"), "test-beta": .fileMissing("exam.json")])
        #expect(result.fatalError == .storage("no usable exam"))
    }

    @Test func brokenStateDoesNotBlockOtherExams() async throws {
        let root = PackFixtures.temporary()
        defer { try? FileManager.default.removeItem(at: root) }
        try FileManager.default.createDirectory(at: root.appending(path: "test-alpha"), withIntermediateDirectories: true)
        try Data("{".utf8).write(to: root.appending(path: "test-alpha/state.json"))
        let result = await bootstrapper(try CatalogFixtures.bundled(), store: PackStore(root: root)).bootstrap()
        #expect(Set(result.available.keys) == ["test-beta"])
        #expect(result.failures["test-alpha"] != nil && result.fatalError == nil)
    }

    @Test func emptyCatalogReportsFatalError() async throws {
        var catalog = try CatalogFixtures.catalog()
        catalog.exams = []
        let result = await bootstrapper(try CatalogFixtures.bundled(catalog: catalog), store: PackStore(root: PackFixtures.temporary())).bootstrap()
        #expect(result.available.isEmpty && result.failures.isEmpty)
        #expect(result.fatalError == .storage("no usable exam"))
    }

    @Test(arguments: ["manifest-exam", "manifest-version", "definition-exam", "vendor"])
    func rejectsMismatchedPackIdentity(field: String) async throws {
        let root = PackFixtures.temporary()
        defer { try? FileManager.default.removeItem(at: root) }
        let bundled = try copiedBundle(root)
        let directory = bundled.root.appending(path: "test-alpha/1.0.0")
        let filename = field.hasPrefix("manifest") ? "manifest.json" : field == "vendor" ? "vendor.json" : "exam.json"
        let path = directory.appending(path: filename)
        var object = try #require(JSONSerialization.jsonObject(with: Data(contentsOf: path)) as? [String: Any])
        let key = field == "manifest-exam" ? "examID" : field == "manifest-version" ? "packVersion" : "id"
        object[key] = field == "manifest-version" ? "9.0.0" : "other-exam"
        try JSONSerialization.data(withJSONObject: object).write(to: path)
        let store = PackStore(root: root.appending(path: "store"))
        let result = await bootstrapper(bundled, store: store).bootstrap()
        #expect(result.available["test-alpha"] == nil && result.failures["test-alpha"] != nil)
        #expect(result.available["test-beta"] != nil)
        #expect(try await store.state(for: "test-alpha").current == nil)
    }
}
