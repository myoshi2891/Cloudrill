import Foundation
import Testing
import DomainModels
import DomainInterfaces
@testable import ContentKit

struct ExamContentResolverTests {
    @Test func resolvesOldBundledVersionWithoutActivatingIt() async throws {
        let root = PackFixtures.temporary()
        defer { try? FileManager.default.removeItem(at: root) }
        let catalog = try BundledPacks(root: PackFixtures.root).catalog
        let store = PackStore(root: root)
        try await store.activate(.init(source: .bundled, version: "1.1.0"), for: "test-alpha")
        let resolver = ExamContentResolver(bundled: BundledPacks(root: PackFixtures.root.appending(path: "valid"), catalog: catalog),
            store: store, supportedKinds: Set(QuestionKind.allCases))
        let content = try await resolver.content(for: "test-alpha", version: "1.0.0")
        #expect(content.packVersion == "1.0.0")
        #expect(content.definition.id == "test-alpha")
        #expect(try await store.state(for: "test-alpha").current?.version == "1.1.0")
        await #expect(throws: ContentError.self) { try await resolver.content(for: "test-alpha", version: "9.9.9") }
        await #expect(throws: ContentError.self) { try await resolver.content(for: "../escape", version: "1.0.0") }
    }

    @Test func resolvesInstalledVersionAndRejectsIdentityMismatch() async throws {
        let root = PackFixtures.temporary()
        defer { try? FileManager.default.removeItem(at: root) }
        let catalog = try BundledPacks(root: PackFixtures.root).catalog
        let store = PackStore(root: root)
        let staging = root.appending(path: "test-alpha/staging/\(UUID())")
        try FileManager.default.createDirectory(at: staging.deletingLastPathComponent(), withIntermediateDirectories: true)
        try FileManager.default.copyItem(at: PackFixtures.valid(), to: staging)
        try await store.install(staged: staging, version: "1.0.0", for: "test-alpha")
        let resolver = ExamContentResolver(bundled: BundledPacks(root: root.appending(path: "no-bundle"), catalog: catalog),
            store: store, supportedKinds: Set(QuestionKind.allCases))
        #expect(try await resolver.content(for: "test-alpha", version: "1.0.0").packVersion == "1.0.0")
        let wrong = root.appending(path: "test-alpha/staging/\(UUID())")
        try FileManager.default.copyItem(at: PackFixtures.valid("test-beta"), to: wrong)
        try await store.install(staged: wrong, version: "1.1.0", for: "test-alpha")
        await #expect(throws: ContentError.self) { try await resolver.content(for: "test-alpha", version: "1.1.0") }
    }

    @Test func pinnedBundledVersionResolvesAfterBundleChanges() async throws {
        // Arrange
        let root = PackFixtures.temporary()
        defer { try? FileManager.default.removeItem(at: root) }
        let catalog = try BundledPacks(root: PackFixtures.root).catalog
        let store = PackStore(root: root, bundledRoot: PackFixtures.root.appending(path: "valid"))
        try await store.activate(.init(source: .bundled, version: "1.0.0"), for: "test-alpha")
        try await store.pin("1.0.0", for: "test-alpha", attemptID: UUID())
        // Act: アプリ更新で同梱の 1.0.0 が消えた状態を、同梱なしのルートで再現する。
        let resolver = ExamContentResolver(bundled: BundledPacks(root: root.appending(path: "no-bundle"), catalog: catalog),
            store: store, supportedKinds: Set(QuestionKind.allCases))
        // Assert
        #expect(try await resolver.content(for: "test-alpha", version: "1.0.0").packVersion == "1.0.0")
    }
}
