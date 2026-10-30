import Testing
import AppCore
import ExamFeature

@MainActor struct ExplanationViewModelTests {
    @Test func allRationalesTagsSelectionAndOriginalOrderAreShown() async throws {
        let h = try ResultHarness()
        let model = h.explanation("Q1")
        await model.load()
        #expect(model.error == nil)
        #expect(model.question?.revision == 7)
        #expect(model.choices.map(\.id) == ["d", "c", "b", "a"])
        #expect(model.choices.allSatisfy { !$0.rationale.ja.isEmpty })
        #expect(model.choices.first { $0.id == "b" }?.mistakeTags == [.cost, .opsOverhead])
        #expect(model.selectedIDs == ["b"])
        #expect(model.isCorrect == false)
        #expect(h.resolver.requests.withLock { $0 } == ["1.0.0"])
    }
    @Test func addToCardsIsIdempotentAndCanRetryFailure() async throws {
        let h = try ResultHarness()
        let model = h.explanation()
        await model.load()
        await h.cards.fail(on: "Q0")
        await model.addToCards()
        #expect(!model.isAddedToCards)
        #expect(model.actionError != nil)
        await h.cards.fail(on: nil)
        await model.addToCards()
        await model.addToCards()
        #expect(model.isAddedToCards)
        #expect(model.actionError == nil)
        #expect(await h.cards.added == ["Q0"])
    }
    @Test func disabledCardsAndAbsentDocsOfferNoActions() async throws {
        let h = try ResultHarness(flashcards: false, docs: false)
        let model = h.explanation()
        await model.load()
        #expect(!model.canAddToCards)
        #expect(model.relatedDoc == nil)
        await model.addToCards()
        model.openRelatedDoc()
        #expect(await h.cards.added.isEmpty)
        #expect(h.router.path(for: .learn).isEmpty)
    }
    @Test func reportContextAndRelatedDocRoute() async throws {
        let h = try ResultHarness()
        let model = h.explanation()
        await model.load()
        model.openReport()
        #expect(model.report?.examID == "test-alpha")
        #expect(model.report?.questionID == "Q0")
        #expect(model.report?.questionRevision == 7)
        #expect(model.report?.packVersion == "1.0.0")
        model.closeReport()
        #expect(model.report == nil)
        model.openRelatedDoc()
        #expect(h.router.path(for: .learn) == [.doc(subObjective: "3.2")])
    }
    @Test func disabledDocsAreHiddenEvenWhenIndexHasAnEntry() async throws {
        let h = try ResultHarness(docsEnabled: false)
        let model = h.explanation()
        await model.load()
        #expect(model.relatedDoc == nil)
    }
    @Test func questionOutsideAttemptCannotRevealExplanation() async throws {
        let h = try ResultHarness()
        let model = h.explanation("unknown")
        await model.load()
        #expect(model.question == nil)
        #expect(model.error != nil)
        model.openReport()
        #expect(model.report == nil)
    }
}
