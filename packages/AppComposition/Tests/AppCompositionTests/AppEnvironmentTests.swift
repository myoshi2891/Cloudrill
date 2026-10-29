import Foundation
import Testing
import DomainModels
import StudyModels
import ContentKit
import AppCore
import ExamFeature
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

    @Test func startsAndAbandonsWithRealRepositoriesAndPins() async throws {
        let root = temporary()
        defer { try? FileManager.default.removeItem(at: root) }
        let environment = try await AppEnvironment.uiTesting(arguments: ["-ui-testing", "-content-fixture", "test-beta", "-store-in-memory"],
            packsRoot: Self.packs, workingDirectory: root)
        let content = try #require(environment.activeExam.content)
        let deps = environment.dependencies
        let model = ExamStartViewModel(content: content, examSet: 1, attempts: deps.attempts,
            pins: deps.pins, settings: deps.settings, time: deps.time, seedProvider: deps.seedProvider, router: environment.activeExam.router)
        await model.start()
        #expect(model.error == nil)
        let attempt = try #require(try await deps.attempts.inProgress(examID: "test-beta"))
        #expect(attempt.snapshot.order.items.count == 40)
        #expect(try await environment.packStore.state(for: "test-beta").pins[attempt.id] == "1.0.0")
        await model.abandon()
        #expect(try await deps.attempts.inProgress(examID: "test-beta") == nil)
        #expect(try await environment.packStore.state(for: "test-beta").pins.isEmpty)
    }

    @Test func sessionRestoresDiskAnswersAndSubmitsAfterExpiry() async throws {
        let root = temporary()
        defer { try? FileManager.default.removeItem(at: root) }
        let args = ["-ui-testing", "-content-fixture", "test-beta", "-store-path", root.path,
                    "-fixed-now", "2026-11-01T09:00:00Z"]
        let first = try await AppEnvironment.uiTesting(arguments: args, packsRoot: Self.packs, workingDirectory: root)
        let deps = first.dependencies
        let start = ExamStartViewModel(content: try #require(first.activeExam.content), examSet: 1,
            attempts: deps.attempts, pins: deps.pins, settings: deps.settings, time: deps.time,
            seedProvider: deps.seedProvider, router: first.activeExam.router)
        await start.start()
        let attempt = try #require(try await deps.attempts.inProgress(examID: "test-beta"))
        let session = ExamSessionViewModel(examID: "test-beta", attemptID: attempt.id, contentResolver: deps.contentResolver,
            attempts: deps.attempts, pins: deps.pins, cards: deps.cards, settings: deps.settings, time: deps.time, router: first.activeExam.router)
        await session.load()
        let choice = try #require(session.state.question?.choices.first?.id)
        await session.select(choiceID: choice)
        await session.toggleFlag()
        await session.move(to: 4)
        await session.scenePhaseChanged(isActive: false)
        #expect(session.state.alert == nil)
        let reopened = try await AppEnvironment.uiTesting(arguments: args + ["-advance-on-launch", "61"], packsRoot: Self.packs, workingDirectory: root)
        let restored = ExamSessionViewModel(examID: "test-beta", attemptID: attempt.id, contentResolver: reopened.dependencies.contentResolver,
            attempts: reopened.dependencies.attempts, pins: reopened.dependencies.pins, cards: reopened.dependencies.cards, settings: reopened.dependencies.settings, time: reopened.dependencies.time, router: reopened.activeExam.router)
        await restored.load()
        #expect(restored.state.currentIndex == 4)
        #expect(restored.state.remainingSeconds == 5339)
        await restored.move(to: 0)
        #expect(restored.state.selected == [choice])
        #expect(restored.state.isFlagged)
        await restored.scenePhaseChanged(isActive: false)
        let expired = try await AppEnvironment.uiTesting(arguments: args + ["-advance-on-launch", "5401"], packsRoot: Self.packs, workingDirectory: root)
        let expiredSession = ExamSessionViewModel(examID: "test-beta", attemptID: attempt.id, contentResolver: expired.dependencies.contentResolver,
            attempts: expired.dependencies.attempts, pins: expired.dependencies.pins, cards: expired.dependencies.cards, settings: expired.dependencies.settings, time: expired.dependencies.time, router: expired.activeExam.router)
        await expiredSession.load()
        #expect(expiredSession.state.alert == nil)
        #expect(try await expired.dependencies.attempts.inProgress(examID: "test-beta") == nil)
        #expect(try await expired.dependencies.attempts.history(examID: "test-beta").first?.reason == .timeExpired)
        #expect(try await expired.packStore.state(for: "test-beta").pins.isEmpty)
        #expect(expired.activeExam.router.path(for: .exam) == [.examResult(attemptID: attempt.id)])
    }

    @Test func reviewAndManualSubmissionUseSharedSessionAndPersistCards() async throws {
        let root = temporary()
        defer { try? FileManager.default.removeItem(at: root) }
        let args = ["-ui-testing", "-content-fixture", "test-beta", "-store-path", root.path]
        let environment = try await AppEnvironment.uiTesting(arguments: args, packsRoot: Self.packs, workingDirectory: root)
        let deps = environment.dependencies
        let content = try #require(environment.activeExam.content)
        let start = ExamStartViewModel(content: content, examSet: 1, attempts: deps.attempts,
            pins: deps.pins, settings: deps.settings, time: deps.time, seedProvider: deps.seedProvider,
            router: environment.activeExam.router)
        await start.start()
        let attempt = try #require(try await deps.attempts.inProgress(examID: "test-beta"))
        let store = ExamSessionStore(examID: "test-beta", dependencies: deps, router: environment.activeExam.router)
        let session = store.model(for: attempt.id)
        #expect(store.model(for: attempt.id) === session)
        await session.load()
        let questionID = try #require(session.state.question?.id)
        let question = try #require(try await content.questions(ids: [questionID]).first)
        let wrong = try #require(question.choices.first { !$0.isCorrect })
        await session.select(choiceID: wrong.id)
        await session.toggleFlag()
        await session.openReview()
        await session.viewDisappeared() // 見直しへのpushで中断しない。
        #expect(session.state.sessionState == .reviewing)
        let review = ExamReviewViewModel(session: store.model(for: attempt.id))
        await review.load()
        #expect(review.state.unansweredCount == 39)
        #expect(review.state.flaggedCount == 1)
        await review.jumpToQuestion(index: 10)
        await session.showQuestions()
        #expect(session.state.currentIndex == 10)
        await session.openReview()
        review.submitTapped()
        await review.confirmSubmit()
        #expect(session.state.alert == nil)
        #expect(environment.activeExam.router.path(for: .exam) == [.examResult(attemptID: attempt.id)])
        let reopened = try await AppEnvironment.uiTesting(arguments: args, packsRoot: Self.packs, workingDirectory: root)
        let history = try await reopened.dependencies.attempts.history(examID: "test-beta")
        #expect(history.count == 1)
        #expect(history.first?.reason == .user)
        #expect(history.first?.total.total == 40)
        #expect(try await reopened.dependencies.cards.card(id: "Q:" + questionID, examID: "test-beta") != nil)
        #expect(try await reopened.dependencies.cards.scheduledCards(examID: "test-beta").count == 1)
        #expect(try await reopened.packStore.state(for: "test-beta").pins.isEmpty)
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
