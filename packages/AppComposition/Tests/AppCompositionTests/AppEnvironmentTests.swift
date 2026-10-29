import Foundation
import Testing
import DomainModels
import StudyModels
import ContentKit
import AppCore
@testable import AppComposition

@MainActor struct AppEnvironmentTests {
    static let packs = URL(fileURLWithPath: #filePath).deletingLastPathComponent()
        .appending(path: "../../../../ExamPrepApp/Resources/Packs").standardizedFileURL
    private func temporary() -> URL { FileManager.default.temporaryDirectory.appending(path: "app-environment-\(UUID())") }

    @Test func uiTestingParsesArgumentsAndBootstrapsFixture() async throws {
        let root = temporary()
        defer { try? FileManager.default.removeItem(at: root) }
        let environment = try await AppEnvironment.uiTesting(arguments: ["-ui-testing", "-fixed-now", "2026-11-01T09:00:00Z",
            "-advance-on-launch", "7200", "-content-fixture", "test-alpha", "-store-in-memory", "-network", "offline"],
            packsRoot: Self.packs, workingDirectory: root)
        #expect(environment.dependencies.time.now() == ISO8601DateFormatter().date(from: "2026-11-01T11:00:00Z"))
        #expect(environment.isInMemory)
        #expect(environment.activeExam.state.examID == "test-alpha")
        #expect(environment.activeExam.content?.packVersion == "1.0.0")
        #expect(environment.activeExam.state.fatal == nil)
        #expect(!FileManager.default.fileExists(atPath: root.appending(path: "StudyHistory.store").path))
    }

    @Test func diskConfigurationRestoresLastSelection() async throws {
        let root = temporary()
        defer { try? FileManager.default.removeItem(at: root) }
        let args = ["-ui-testing", "-store-path", root.appending(path: "history").path]
        let first = try await AppEnvironment.uiTesting(arguments: args, packsRoot: Self.packs, workingDirectory: root)
        #expect(first.activeExam.state.needsSelection)
        await first.activeExam.switchExam(to: "test-beta")
        let reopened = try await AppEnvironment.uiTesting(arguments: args, packsRoot: Self.packs, workingDirectory: root)
        #expect(!reopened.isInMemory)
        #expect(reopened.activeExam.state.examID == "test-beta")
    }

    @Test func supportedKindsMatchBothRegistries() {
        #expect(AppEnvironment.supportedKinds == Set(QuestionKind.allCases))
    }

    @Test func bundledPacksArePresentAndSignaturesVerify() throws {
        let bundled = try BundledPacks(root: Self.packs)
        let keys = try PublicKeyRing(data: Data(contentsOf: Self.packs.appending(path: "test-keys.json")))
        let version = try #require(SemanticVersion("1.0.0"))
        let verifier = PackVerifier(keyRing: keys, appVersion: version, supportedFormatVersion: 1)
        for entry in bundled.catalog.exams where entry.status == .available {
            let packVersion = try #require(entry.latestPackVersion)
            let manifest = try verifier.verify(packAt: Self.packs.appending(path: "\(entry.id)/\(packVersion)"),
                                               expectedExamID: entry.id, currentVersion: nil)
            #expect(manifest.examID == entry.id)
        }
    }

    @Test func liveRejectsDevelopmentBundle() async throws {
        let root = temporary()
        defer { try? FileManager.default.removeItem(at: root) }
        await #expect(throws: AppEnvironmentError.developmentContentNotAllowed) {
            try await AppEnvironment.live(packsRoot: Self.packs, storeDirectory: root)
        }
    }

    @Test func developmentUsesSystemTimeAndRealRepositories() async throws {
        let root = temporary()
        defer { try? FileManager.default.removeItem(at: root) }
        let environment = try await AppEnvironment.development(packsRoot: Self.packs, storeDirectory: root)
        #expect(environment.dependencies.time is SystemTimeSource)
        await environment.activeExam.switchExam(to: "test-beta")
        #expect(try await environment.dependencies.settings.settings().currentExamID == "test-beta")
        #expect(FileManager.default.fileExists(atPath: root.appending(path: "StudyHistory.store").path))
    }

    @Test(arguments: [
        ["-fixed-now", "bad"], ["-store-in-memory", "-store-path", "/tmp/history"],
        ["-advance-on-launch", "nan"], ["-advance-on-launch", "-1"], ["-content-fixture", "../escape"],
        ["-store-path", "relative"], ["-network", "online"], ["-fixed-now"], ["-unknown"],
    ]) func invalidArgumentsAreRejected(arguments: [String]) {
        #expect(throws: UITestingConfigurationError.self) { try UITestingConfiguration(arguments: ["-ui-testing"] + arguments) }
    }
}
