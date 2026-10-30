import Foundation
import Testing
import ExamFeature
import AppCore
import StudyModels
import ExamEngine

@MainActor struct ExamReviewViewModelTests {
    @Test func listsUnansweredAndFlaggedAndConfirmsCounts() async throws {
        let h = try SessionHarness(count: 5)
        await h.model.load()
        await h.model.select(choiceID: "a")
        await h.model.toggleFlag()
        await h.model.move(to: 1)
        await h.model.select(choiceID: "b")
        await h.model.toggleFlag()
        await h.model.openReview()
        let review = ExamReviewViewModel(session: h.model)
        #expect(review.state.items.map(\.number) == [1, 2, 3, 4, 5])
        #expect(review.state.items.filter(\.isUnanswered).map(\.number) == [3, 4, 5])
        #expect(review.state.items.filter(\.isFlagged).map(\.number) == [1, 2])
        #expect(review.state.unansweredCount == 3)
        #expect(review.state.flaggedCount == 2)
        #expect(await h.attempts.current?.snapshot.state == .reviewing)
        review.submitTapped()
        #expect(review.state.confirmation?.unansweredCount == 3)
        #expect(review.state.confirmation?.flaggedCount == 2)
        #expect(await h.attempts.finalizations == 0)
        review.cancelSubmit()
        #expect(review.state.confirmation == nil)
    }
    @Test func jumpsToQuestionWithoutReloadingContent() async throws {
        let h = try SessionHarness(count: 12)
        await h.model.load()
        await h.model.openReview()
        let review = ExamReviewViewModel(session: h.model)
        await review.load()
        await review.jumpToQuestion(index: 11)
        #expect(h.model.state.currentIndex == 11)
        #expect(h.model.state.sessionState == .inProgress)
        #expect(await h.attempts.current?.snapshot.currentIndex == 11)
        #expect(h.router.path(for: .exam) == [.examSession(attemptID: h.id)])
        #expect(h.content.reads.withLock { $0 } == 1)
    }
    @Test func confirmSubmitScoresAndCreatesOnlyAnsweredMistakeCards() async throws {
        let h = try SessionHarness(count: 6)
        await h.model.load()
        await h.model.select(choiceID: "a")
        for index in 1...4 {
            await h.model.move(to: index)
            await h.model.select(choiceID: "b")
        }
        await h.model.openReview()
        let review = ExamReviewViewModel(session: h.model)
        await review.confirmSubmit() // ダイアログを経ない提出は受け付けない。
        #expect(await h.attempts.finalizations == 0)
        review.submitTapped()
        await review.confirmSubmit()
        await review.confirmSubmit()
        #expect(await h.attempts.finalizations == 1)
        #expect(await h.attempts.reason == .user)
        #expect(await h.attempts.result?.total == ScoreTally(correct: 1, total: 6))
        #expect(await h.attempts.result?.unansweredCount == 1)
        #expect(await h.cards.added == ["Q1", "Q2", "Q3", "Q4"])
        #expect(await h.pins.pinned == h.id)
        #expect(await h.pins.retained == h.id)
        #expect(h.router.path(for: .exam) == [.examResult(attemptID: h.id)])
    }
    @Test func disabledAutoCards() async throws {
        let h = try SessionHarness()
        await h.settings.setAutoCards(false)
        await h.model.load()
        await h.model.select(choiceID: "b")
        await h.model.openReview()
        let review = ExamReviewViewModel(session: h.model)
        review.submitTapped(); await review.confirmSubmit()
        #expect(await h.cards.added.isEmpty)
        #expect(await h.attempts.reason == .user)
    }
    @Test func disabledFlashcardsDoNotDependOnCardSettings() async throws {
        let h = try SessionHarness(flashcardsEnabled: false)
        await h.settings.fail(true)
        await h.model.load(); await h.model.select(choiceID: "b"); await h.model.openReview()
        let review = ExamReviewViewModel(session: h.model)
        review.submitTapped(); await review.confirmSubmit()
        #expect(await h.attempts.reason == .user)
        #expect(await h.cards.added.isEmpty)
    }
    @Test func systemBackClosesReviewAndAllowsAnswerChanges() async throws {
        let h = try SessionHarness()
        await h.model.load(); await h.model.openReview()
        h.router.setPath([.examSession(attemptID: h.id)], for: .exam)
        await h.model.showQuestions()
        #expect(h.model.state.sessionState == .inProgress)
        #expect(await h.attempts.current?.snapshot.state == .inProgress)
        await h.model.select(choiceID: "a")
        #expect(h.model.state.selected == ["a"])
        #expect(h.content.reads.withLock { $0 } == 1)
    }

    @Test func expiryWhileConfirmingUsesTimeoutAndSharedAutoCards() async throws {
        let h = try SessionHarness(duration: 60)
        await h.model.load()
        await h.model.select(choiceID: "b")
        await h.model.openReview()
        let review = ExamReviewViewModel(session: h.model)
        review.submitTapped()
        h.time.advance(by: .seconds(61))
        await review.confirmSubmit()
        #expect(await h.attempts.reason == .timeExpired)
        #expect(await h.cards.added == ["Q0"])
        #expect(review.state.confirmation == nil)
        #expect(h.router.path(for: .exam) == [.examResult(attemptID: h.id)])
    }
    @Test func reviewBackgroundResumeAndExpiry() async throws {
        let h = try SessionHarness(duration: 60)
        await h.model.load(); await h.model.openReview()
        await h.model.scenePhaseChanged(isActive: false)
        await h.model.scenePhaseChanged(isActive: true)
        #expect(h.model.state.sessionState == .reviewing)
        h.time.advance(by: .seconds(61))
        await h.model.tick()
        #expect(await h.attempts.reason == .timeExpired)
    }
    @Test func failedJumpKeepsReviewAndPosition() async throws {
        let h = try SessionHarness(count: 2)
        await h.model.load(); await h.model.openReview()
        await h.attempts.failSave(true)
        let review = ExamReviewViewModel(session: h.model)
        await review.jumpToQuestion(index: 1)
        #expect(h.model.state.currentIndex == 0)
        #expect(h.model.state.sessionState == .reviewing)
        #expect(h.router.path(for: .exam).last == .examReview(attemptID: h.id))
        await h.attempts.failSave(false)
        await review.jumpToQuestion(index: 1)
        #expect(h.model.state.currentIndex == 1)
    }
    @Test func partialCardFailureRetriesWithoutRefinalizingOrDuplicatingCards() async throws {
        let h = try SessionHarness(count: 2)
        await h.model.load()
        await h.model.select(choiceID: "b"); await h.model.move(to: 1); await h.model.select(choiceID: "b")
        await h.cards.fail(on: "Q1")
        await h.model.openReview()
        let review = ExamReviewViewModel(session: h.model)
        review.submitTapped(); await review.confirmSubmit()
        #expect(await h.attempts.finalizations == 1)
        #expect(await h.cards.added == ["Q0"])
        #expect(await h.pins.pinned == h.id)
        #expect(review.state.alert != nil)
        await h.cards.fail(on: nil)
        await h.settings.setAutoCards(false) // 再試行は最初の提出時に決めた対象を完了する。
        await review.retry()
        #expect(await h.attempts.finalizations == 1)
        #expect(await h.cards.added == ["Q0", "Q1"])
        #expect(h.router.path(for: .exam) == [.examResult(attemptID: h.id)])
    }
    @Test func settingsFailureDoesNotFinalizeOrSilentlySkipCards() async throws {
        let h = try SessionHarness()
        await h.model.load(); await h.model.select(choiceID: "b"); await h.model.openReview()
        await h.settings.fail(true)
        let review = ExamReviewViewModel(session: h.model)
        review.submitTapped(); await review.confirmSubmit()
        #expect(await h.attempts.finalizations == 0)
        await h.settings.fail(false)
        await review.retry()
        #expect(await h.attempts.finalizations == 1)
        #expect(await h.cards.added == ["Q0"])
    }
}
