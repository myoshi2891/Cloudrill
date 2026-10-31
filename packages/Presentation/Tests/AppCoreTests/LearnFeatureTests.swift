import Foundation
import Testing
import Synchronization
import LearnFeature
import AppCore
import DesignSystem
import DomainModels
import DomainInterfaces

@MainActor struct LearnFeatureTests {
    @Test(arguments: [
        ("test-alpha", true, ["docs", "cases"]),
        ("test-beta", true, ["docs"]),
        ("test-beta", false, []),
    ])
    func learnModulesFollowFeatures(exam: String, docs: Bool, expected: [String]) throws {
        // Arrange
        var definition = try ExamFixture(ExamID(rawValue: exam)).definition
        definition.features.docs = docs
        // Act
        let modules = LearnModuleRegistry.standard.modules(for: definition.features)
        // Assert: ツリーとドリルは有効でも P6 まで登録しない
        #expect(modules.map(\.id) == expected)
        #expect(modules.first?.route == (docs ? .docsIndex(domain: nil) : nil))
    }

    @Test func registryAcceptsAdditionalModules() {
        let extra = LearnModule(id: "trees", titleKey: "x", symbol: "tree", route: .caseList)
        let registry = LearnModuleRegistry(entries: [.init(module: extra, isEnabled: { $0.decisionTrees })])
        #expect(registry.modules(for: ExamFeatures(caseStudies: false, docs: false, flashcards: false,
                                                   decisionTrees: true, keywordDrills: false)) == [extra])
    }

    @Test func docsGroupedByDomainAndMissingDocsShown() throws {
        // Arrange: 定義順と逆に索引を並べても、定義の順で出る
        let h = try LearnHarness(docs: [doc("2.1", "ネットワーク"), doc("1.2", "設計")])
        // Act
        let model = DocsIndexViewModel(content: h.content, router: h.router)
        // Assert
        #expect(model.sections.map(\.id) == h.content.definition.domains.map(\.id))
        #expect(model.sections[0].rows.map(\.id) == h.content.definition.domains[0].subObjectives.map(\.id))
        #expect(model.sections[0].rows.first { $0.id == "1.2" }?.title == "設計")
        #expect(model.sections[0].rows.first { $0.id == "1.1" }?.isAvailable == false)
        model.open(model.sections[0].rows[0])
        #expect(h.router.path(for: .learn).isEmpty)
        model.open(try #require(model.sections[1].rows.first { $0.id == "2.1" }))
        #expect(h.router.selectedTab == .learn)
        #expect(h.router.path(for: .learn) == [.doc(subObjective: "2.1")])
    }

    @Test func domainFilterAndDisabledDocs() throws {
        let h = try LearnHarness(docs: [doc("2.1", "ネットワーク")])
        #expect(DocsIndexViewModel(content: h.content, domain: 2, router: h.router).sections.map(\.id) == [2])
        let disabled = try LearnHarness(docs: [doc("2.1", "ネットワーク")], enabled: false)
        let model = DocsIndexViewModel(content: disabled.content, router: disabled.router)
        #expect(!model.isAvailable)
        #expect(model.sections.isEmpty)
    }

    @Test func docShowsBodyAndReferences() async throws {
        let h = try LearnHarness(docs: [doc("1.1", "概要", references: [
            reference("Google Cloud docs", license: "CC-BY-4.0"), reference("Blog", license: "link-only"),
        ])], body: "# 概要\n\n本文")
        let model = DocViewModel(content: h.content, subObjective: "1.1")
        await model.load()
        #expect(model.phase == .loaded(MarkdownDocument(blocks: [.heading(level: 1, text: "概要"), .paragraph("本文")])))
        #expect(model.title == "概要")
        #expect(model.references.map { ReferenceLink.licenseLabel($0.license) } == ["CC BY 4.0", nil])
    }

    @Test func unknownSubObjectiveIsNotFound() async throws {
        let h = try LearnHarness(docs: [doc("1.1", "概要")])
        let model = DocViewModel(content: h.content, subObjective: "9.9")
        await model.load()
        #expect(model.phase == .notFound)
        #expect(h.content.bodyReads == 0)
    }

    @Test func docLoadFailureCanRetry() async throws {
        let h = try LearnHarness(docs: [doc("1.1", "概要")])
        h.content.failBody(true)
        let model = DocViewModel(content: h.content, subObjective: "1.1")
        await model.load()
        #expect(model.phase == .failed)
        h.content.failBody(false)
        await model.load()
        #expect(model.phase == .loaded(MarkdownDocument(blocks: [.paragraph("本文")])))
        await model.load()
        #expect(h.content.bodyReads == 2)
    }

    // MARK: - ケーススタディ(S13)

    @Test func casesInDefinitionOrder() async throws {
        // Arrange: 定義(ehr, altostrat)と逆の順で返し、定義にないケースを混ぜる
        let h = try LearnHarness(docs: [], cases: [caseStudy("altostrat"), caseStudy("extra"), caseStudy("ehr")])
        let model = CaseListViewModel(content: h.content, router: h.router)
        // Act
        await model.load()
        // Assert
        guard case .loaded(let cases) = model.phase else { Issue.record("\(model.phase)"); return }
        #expect(cases.map(\.id) == h.content.definition.caseStudies)
        model.open("altostrat")
        #expect(h.router.selectedTab == .learn)
        #expect(h.router.path(for: .learn) == [.caseDetail("altostrat")])
    }

    @Test func detailShowsSummarySectionsAndOfficialLink() async throws {
        let h = try LearnHarness(docs: [], cases: [caseStudy("ehr"), caseStudy("altostrat")])
        let model = CaseDetailViewModel(content: h.content, id: "altostrat", router: h.router)
        await model.load()
        guard case .loaded(let found) = model.phase else { Issue.record("\(model.phase)"); return }
        // 要約・ビジネス要件・技術要件・既存環境を持ち、全文ではなく公式ページへのリンクを出す(LG-03)
        #expect(found.summary.ja == "altostrat の要約")
        #expect(found.businessRequirements.map(\.ja) == ["事業要件"])
        #expect(found.technicalRequirements.map(\.ja) == ["技術要件"])
        #expect(found.existingEnvironment.ja == "既存環境")
        #expect(found.officialURL == URL(string: "https://example.com/altostrat"))
    }

    @Test func practiceForCase() async throws {
        let h = try LearnHarness(docs: [], cases: [caseStudy("ehr")])
        let model = CaseDetailViewModel(content: h.content, id: "ehr", router: h.router)
        model.practice()
        #expect(h.router.path(for: .exam).isEmpty)  // 読み込み前は何もしない
        await model.load()
        model.practice()
        #expect(h.router.selectedTab == .exam)
        #expect(h.router.path(for: .exam) == [.practiceSetup(.caseStudy("ehr"))])
    }

    @Test func casesNotLoadedWhenDisabled() async throws {
        let h = try LearnHarness(docs: [], cases: [caseStudy("ehr")], casesEnabled: false)
        let list = CaseListViewModel(content: h.content, router: h.router)
        await list.load()
        #expect(!list.isAvailable)
        #expect(list.phase == .idle)
        let detail = CaseDetailViewModel(content: h.content, id: "ehr", router: h.router)
        await detail.load()
        #expect(detail.phase == .notFound)
        #expect(h.content.caseReads == 0)
    }

    @Test func unknownCaseIsNotFound() async throws {
        let h = try LearnHarness(docs: [], cases: [caseStudy("ehr")])
        // 定義にない ID は読み込まない。定義にあってもデータにない ID は notFound
        let unknown = CaseDetailViewModel(content: h.content, id: "zzz", router: h.router)
        await unknown.load()
        #expect(unknown.phase == .notFound)
        #expect(h.content.caseReads == 0)
        let missing = CaseDetailViewModel(content: h.content, id: "altostrat", router: h.router)
        await missing.load()
        #expect(missing.phase == .notFound)
    }

    @Test func caseLoadFailureCanRetry() async throws {
        let h = try LearnHarness(docs: [], cases: [caseStudy("ehr")])
        h.content.failCases(true)
        let list = CaseListViewModel(content: h.content, router: h.router)
        let detail = CaseDetailViewModel(content: h.content, id: "ehr", router: h.router)
        await list.load(); await detail.load()
        #expect(list.phase == .failed)
        #expect(detail.phase == .failed)
        h.content.failCases(false)
        await list.load(); await detail.load()
        #expect(list.phase == .loaded([caseStudy("ehr")]))
        #expect(detail.phase == .loaded(caseStudy("ehr")))
        await list.load(); await detail.load()
        #expect(h.content.caseReads == 4)
    }
}

// MARK: - Support

private func reference(_ title: String, license: String) -> String {
    "{\"title\":\"\(title)\",\"url\":\"https://example.com/\(title.count)\",\"license\":\"\(license)\"}"
}

private func doc(_ sub: String, _ title: String, references: [String] = []) -> DocEntry {
    let json = "{\"subObjective\":\"\(sub)\",\"title\":\"\(title)\",\"references\":[\(references.joined(separator: ","))],\"path\":\"docs/\(sub).md\"}"
    // 固定の JSON なので失敗しない。失敗した場合はテストの記述の誤り
    do { return try JSONDecoder().decode(DocEntry.self, from: Data(json.utf8)) } catch { fatalError("\(error)") }
}

private func caseStudy(_ id: String) -> CaseStudy {
    let json = """
    {"id":"\(id)","name":{"ja":"\(id)"},"summary":{"ja":"\(id) の要約"},"businessRequirements":[{"ja":"事業要件"}],\
    "technicalRequirements":[{"ja":"技術要件"}],"existingEnvironment":{"ja":"既存環境"},\
    "officialURL":"https://example.com/\(id)","requirementMappings":[]}
    """
    // 固定の JSON なので失敗しない。失敗した場合はテストの記述の誤り
    do { return try JSONDecoder().decode(CaseStudy.self, from: Data(json.utf8)) } catch { fatalError("\(error)") }
}

@MainActor private struct LearnHarness {
    let content: LearnContent
    let router = AppRouter()
    init(docs: [DocEntry], body: String = "本文", enabled: Bool = true,
         cases: [CaseStudy] = [], casesEnabled: Bool = true) throws {
        var base = try ExamFixture("test-alpha")
        base.definition.features.docs = enabled
        base.definition.features.caseStudies = casesEnabled
        base.docsIndex = docs
        content = LearnContent(base: base, body: body, cases: cases)
    }
}

private final class LearnContent: ExamContentProvider, Sendable {
    let base: ExamFixture
    let body: String
    let cases: [CaseStudy]
    private let reads = Mutex(0)
    private let fails = Mutex(false)
    private let caseReadCount = Mutex(0)
    private let caseFails = Mutex(false)
    init(base: ExamFixture, body: String, cases: [CaseStudy]) { self.base = base; self.body = body; self.cases = cases }
    var bodyReads: Int { reads.withLock { $0 } }
    var caseReads: Int { caseReadCount.withLock { $0 } }
    func failBody(_ value: Bool) { fails.withLock { $0 = value } }
    func failCases(_ value: Bool) { caseFails.withLock { $0 = value } }
    var definition: ExamDefinition { base.definition }
    var vendor: Vendor { base.vendor }
    var packVersion: String { "1.0.0" }
    var questionIndex: [QuestionIndexEntry] { [] }
    var examSets: [ExamSet] { [] }
    var docsIndex: [DocEntry] { base.docsIndex }
    func questions(ids: [String]) async throws(ContentError) -> [Question] { [] }
    func flashcards() async throws(ContentError) -> [Flashcard] { [] }
    func caseStudies() async throws(ContentError) -> [CaseStudy] {
        caseReadCount.withLock { $0 += 1 }
        if caseFails.withLock({ $0 }) { throw .fileMissing("cases.json") }
        return cases
    }
    func decisionTrees() async throws(ContentError) -> [DecisionTree] { [] }
    func keywordDrills() async throws(ContentError) -> [KeywordDrill] { [] }
    func docBody(for entry: DocEntry) async throws(ContentError) -> String {
        reads.withLock { $0 += 1 }
        if fails.withLock({ $0 }) { throw .fileMissing(entry.path) }
        return body
    }
}
