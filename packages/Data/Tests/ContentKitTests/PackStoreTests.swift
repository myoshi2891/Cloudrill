import Foundation
import Testing
import DomainModels
import DomainInterfaces
@testable import ContentKit

struct PackStoreTests {
    private func staged(_ root: URL, exam: String = "test-alpha") throws -> URL {
        let path = root.appending(path: "\(exam)/staging/\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: path, withIntermediateDirectories: true)
        try Data("verified pack".utf8).write(to: path.appending(path: "marker"))
        return path
    }
    private func install(_ store: PackStore, root: URL, version: String, exam: ExamID = "test-alpha") async throws {
        try await store.install(staged: staged(root, exam: exam.rawValue), version: version, for: exam)
    }
    @Test func initialStateIsEmpty() async throws {
        let root = PackFixtures.temporary()
        let state = try await PackStore(root: root).state(for: "test-alpha")
        #expect(state.current == nil && state.previous == nil && state.pins.isEmpty)
        #expect(!FileManager.default.fileExists(atPath: root.path))
    }
    @Test func installMovesStagingIntoVersions() async throws {
        let root = PackFixtures.temporary()
        defer { try? FileManager.default.removeItem(at: root) }
        let stage = try staged(root)
        let store = PackStore(root: root)
        try await store.install(staged: stage, version: "1.0.0", for: "test-alpha")
        #expect(!FileManager.default.fileExists(atPath: stage.path))
        #expect(FileManager.default.fileExists(atPath: root.appending(path: "test-alpha/versions/1.0.0/marker").path))
    }
    @Test func installRefusesExistingVersion() async throws {
        let root = PackFixtures.temporary()
        defer { try? FileManager.default.removeItem(at: root) }
        let store = PackStore(root: root)
        try await install(store, root: root, version: "1.0.0")
        await #expect(throws: ContentError.storage("1.0.0 already installed")) { try await install(store, root: root, version: "1.0.0") }
    }
    @Test func activateShiftsPreviousAndSurvivesReopen() async throws {
        let root = PackFixtures.temporary()
        defer { try? FileManager.default.removeItem(at: root) }
        let store = PackStore(root: root)
        try await store.activate(.init(source: .bundled, version: "1.0.0"), for: "test-alpha")
        try await install(store, root: root, version: "1.1.0")
        try await store.activate(.init(source: .installed, version: "1.1.0"), for: "test-alpha")
        let state = try await PackStore(root: root).state(for: "test-alpha")
        #expect(state.current == .init(source: .installed, version: "1.1.0"))
        #expect(state.previous == .init(source: .bundled, version: "1.0.0"))
        try await store.activate(.init(source: .installed, version: "1.1.0"), for: "test-alpha")
        #expect(try await store.state(for: "test-alpha") == state) // 再起動時の再有効化で previous を失わない。
    }
    @Test func activateIsAtomic() async throws {
        let root = PackFixtures.temporary()
        let exam = root.appending(path: "test-alpha")
        defer {
            try? FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: exam.path)
            try? FileManager.default.removeItem(at: root)
        }
        let store = PackStore(root: root)
        try await store.activate(.init(source: .bundled, version: "1.0.0"), for: "test-alpha")
        let file = exam.appending(path: "state.json")
        let before = try Data(contentsOf: file)
        try FileManager.default.setAttributes([.posixPermissions: 0o555], ofItemAtPath: exam.path)
        await #expect(throws: ContentError.self) { try await store.activate(.init(source: .bundled, version: "1.1.0"), for: "test-alpha") }
        #expect(try Data(contentsOf: file) == before)
    }
    @Test func pinKeepsVersionAndUnpinAllowsRemoval() async throws {
        let root = PackFixtures.temporary()
        defer { try? FileManager.default.removeItem(at: root) }
        let store = PackStore(root: root)
        let attempt = UUID()
        for version in ["1.0.0", "1.1.0", "1.2.0"] {
            try await install(store, root: root, version: version)
            try await store.activate(.init(source: .installed, version: version), for: "test-alpha")
            if version == "1.0.0" { try await store.pin(version, for: "test-alpha", attemptID: attempt) }
        }
        try await store.garbageCollect(for: "test-alpha")
        let versions = root.appending(path: "test-alpha/versions")
        #expect(try FileManager.default.contentsOfDirectory(atPath: versions.path).sorted() == ["1.0.0", "1.1.0", "1.2.0"])
        let reopened = PackStore(root: root)
        #expect(try await reopened.state(for: "test-alpha").pins[attempt] == "1.0.0")
        let json = try #require(JSONSerialization.jsonObject(with: Data(contentsOf: root.appending(path: "test-alpha/state.json"))) as? [String: Any])
        #expect((json["pins"] as? [String: String])?[attempt.uuidString] == "1.0.0")
        try await reopened.unpin(attemptID: attempt, for: "test-alpha")
        try await reopened.garbageCollect(for: "test-alpha")
        #expect(try FileManager.default.contentsOfDirectory(atPath: versions.path).sorted() == ["1.1.0", "1.2.0"])
    }
    @Test func pinCopiesBundledVersionIntoStore() async throws {
        // Arrange
        let root = PackFixtures.temporary()
        defer { try? FileManager.default.removeItem(at: root) }
        let store = PackStore(root: root, bundledRoot: PackFixtures.root.appending(path: "valid"))
        try await store.activate(.init(source: .bundled, version: "1.0.0"), for: "test-alpha")
        // Act
        try await store.pin("1.0.0", for: "test-alpha", attemptID: UUID())
        // Assert
        #expect(FileManager.default.fileExists(atPath: root.appending(path: "test-alpha/versions/1.0.0/manifest.json").path))
        #expect(try FileManager.default.contentsOfDirectory(atPath: root.appending(path: "test-alpha/staging").path).isEmpty)
        #expect(try await store.state(for: "test-alpha").current == .init(source: .bundled, version: "1.0.0"))
    }
    @Test func pinRejectsUnavailableOrMismatchedVersion() async throws {
        // Arrange
        let root = PackFixtures.temporary()
        defer { try? FileManager.default.removeItem(at: root) }
        let bundle = root.appending(path: "bundle")
        try FileManager.default.createDirectory(at: bundle.appending(path: "test-alpha"), withIntermediateDirectories: true)
        try FileManager.default.copyItem(at: PackFixtures.valid("test-beta"), to: bundle.appending(path: "test-alpha/2.0.0"))
        let unbundled = PackStore(root: root.appending(path: "a"))
        let mismatched = PackStore(root: root.appending(path: "b"), bundledRoot: bundle)
        try await unbundled.activate(.init(source: .bundled, version: "1.0.0"), for: "test-alpha")
        // Act / Assert
        await #expect(throws: ContentError.self) { try await unbundled.pin("1.0.0", for: "test-alpha", attemptID: UUID()) }
        await #expect(throws: ContentError.self) { try await mismatched.pin("9.9.9", for: "test-alpha", attemptID: UUID()) }
        await #expect(throws: ContentError.storage("pack manifest identity mismatch")) {
            try await mismatched.pin("2.0.0", for: "test-alpha", attemptID: UUID())
        }
        #expect(try await unbundled.state(for: "test-alpha").pins.isEmpty)
        #expect(try await mismatched.state(for: "test-alpha").pins.isEmpty)
        #expect(try FileManager.default.contentsOfDirectory(atPath: root.appending(path: "b/test-alpha/staging").path).isEmpty)
        #expect(!FileManager.default.fileExists(atPath: root.appending(path: "b/test-alpha/versions/2.0.0").path))
    }
    @Test func retainKeepsLatestSubmittedAttempts() async throws {
        // Arrange
        let root = PackFixtures.temporary()
        defer { try? FileManager.default.removeItem(at: root) }
        let store = PackStore(root: root, retainedLimit: 2)
        let attempts = [UUID(), UUID(), UUID()]
        for (attempt, version) in zip(attempts, ["1.0.0", "1.1.0", "1.2.0"]) {
            try await install(store, root: root, version: version)
            try await store.pin(version, for: "test-alpha", attemptID: attempt)
        }
        // Act
        for attempt in attempts { try await store.retain(attemptID: attempt, for: "test-alpha") }
        try await store.retain(attemptID: attempts[2], for: "test-alpha") // 提出の再試行は保持順を変えない。
        try await store.retain(attemptID: UUID(), for: "test-alpha")       // 固定のない受験は何もしない。
        try await store.garbageCollect(for: "test-alpha")
        // Assert
        let state = try await PackStore(root: root).state(for: "test-alpha")
        #expect(state.retained == [attempts[1], attempts[2]])
        #expect(state.pins == [attempts[1]: "1.1.0", attempts[2]: "1.2.0"])
        let versions = root.appending(path: "test-alpha/versions")
        #expect(try FileManager.default.contentsOfDirectory(atPath: versions.path).sorted() == ["1.1.0", "1.2.0"])
        try await store.unpin(attemptID: attempts[1], for: "test-alpha")
        #expect(try await store.state(for: "test-alpha").retained == [attempts[2]])
    }
    @Test func stateWithoutRetainedDecodes() throws {
        let id = UUID()
        let state = try JSONDecoder().decode(PackState.self, from: Data("{\"pins\":{\"\(id.uuidString)\":\"1.0.0\"}}".utf8))
        #expect(state.pins == [id: "1.0.0"] && state.retained.isEmpty)
    }
    @Test func bundledIsNeverDeletedAndRollback() async throws {
        let root = PackFixtures.temporary()
        defer { try? FileManager.default.removeItem(at: root) }
        let store = PackStore(root: root)
        let bundled = PackLocation(source: .bundled, version: "1.0.0")
        try await store.activate(bundled, for: "test-alpha")
        try await install(store, root: root, version: "1.1.0")
        try await store.activate(.init(source: .installed, version: "1.1.0"), for: "test-alpha")
        try await store.garbageCollect(for: "test-alpha")
        #expect(try await store.directory(for: bundled, examID: "test-alpha", bundledRoot: PackFixtures.root.appending(path: "valid")) == PackFixtures.valid())
        #expect(FileManager.default.fileExists(atPath: PackFixtures.valid().path))
        try await store.rollback(for: "test-alpha")
        let state = try await store.state(for: "test-alpha")
        #expect(state.current == bundled && state.previous == nil)
    }
    @Test func perExamIsolation() async throws {
        let root = PackFixtures.temporary()
        defer { try? FileManager.default.removeItem(at: root) }
        let store = PackStore(root: root)
        try await store.activate(.init(source: .bundled, version: "1.0.0"), for: "test-alpha")
        #expect(try await store.state(for: "test-beta").current == nil)
    }
    @Test func refusesUnsafeLocations() async throws {
        let root = PackFixtures.temporary()
        let store = PackStore(root: root)
        await #expect(throws: ContentError.self) { try await store.state(for: "../outside") }
        await #expect(throws: ContentError.self) { try await store.activate(.init(source: .installed, version: "../outside"), for: "test-alpha") }
        #expect(!FileManager.default.fileExists(atPath: root.path))
    }
    @Test func refusesMissingInstalledVersion() async throws {
        let store = PackStore(root: PackFixtures.temporary())
        await #expect(throws: ContentError.self) { try await store.activate(.init(source: .installed, version: "1.0.0"), for: "test-alpha") }
    }
}
