import Foundation
import Testing
@testable import DomainModels

/// content/tests/fixtures/valid を JSON に変換したもの(content/scripts/export_json.py で生成)をデコードできること。
@Suite("valid fixture のデコード")
struct FixtureDecodingTests {
    let root: URL
    let decoder = ContentDecoder.make()

    init() throws {
        // このファイル(packages/DomainModels/Tests/DomainModelsTests/)から見たパッケージのルート
        let packageRoot = URL(filePath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        // 試験ごとのディレクトリの列挙は P0-S09 で行う。それまでは test-alpha だけを読む
        root = packageRoot.appending(path: "../../content/tests/fixtures/valid-json/exams/test-alpha").standardized
        let exists = FileManager.default.fileExists(atPath: root.appending(path: "exam-sets.json").path)
        try #require(exists, "フィクスチャがありません: \(root.path)。content/scripts/export_json.py を実行してください")
    }

    private func jsonFiles(in directory: String) throws -> [URL] {
        let base = root.appending(path: directory)
        let enumerator = try #require(FileManager.default.enumerator(at: base, includingPropertiesForKeys: nil))
        return enumerator
            .compactMap { $0 as? URL }
            .filter { $0.pathExtension == "json" }
            .sorted { $0.path < $1.path }
    }

    private func decode<T: Decodable>(_ type: T.Type, _ url: URL) throws -> T {
        try decoder.decode(type, from: Data(contentsOf: url))
    }

    @Test("全問題をデコードでき、模試 1 の 55 問がそろう")
    func questionsAndExamSets() throws {
        // Arrange
        let files = try jsonFiles(in: "questions")
        // Act
        let questions = try files.map { try decode(Question.self, $0) }
        let examSets = try decode(ExamSetsFile.self, root.appending(path: "exam-sets.json"))
        // Assert
        #expect(questions.count == 58)
        let ids = Set(questions.map(\.id))
        let set1 = try #require(examSets.examSets.first { $0.id == 1 })
        #expect(set1.status == .complete)
        #expect(set1.caseStudies == [.ehr, .altostrat])
        #expect(set1.questionIDs.count == 55)
        #expect(set1.questionIDs.allSatisfy { ids.contains($0) })
        #expect(questions.contains { $0.type == .multiple(count: 2) })
        #expect(questions.contains { $0.caseStudy == nil })
        for question in questions {
            #expect(question.correctChoiceIDs.count == question.type.requiredSelections, "\(question.id)")
            let correctHaveNoTags = question.choices.filter(\.isCorrect).allSatisfy { $0.mistakeTags.isEmpty }
            #expect(correctHaveNoTags, "\(question.id)")
        }
    }

    @Test("ドメイン比重のキーが Int 1〜6 で、合計が 1.0")
    func weights() throws {
        let weights = try decode(DomainWeights.self, root.appending(path: "weights.json"))
        #expect(weights.weights.keys.sorted() == Array(1...6))
        #expect(abs(weights.weights.values.reduce(0, +) - 1.0) < 0.001)
    }

    @Test("フラッシュカード・ケース・ツリー・ドリルをデコードできる")
    func otherContent() throws {
        let cards = try jsonFiles(in: "flashcards").flatMap { try decode(FlashcardFile.self, $0).cards }
        #expect(cards.count == 2)

        let cases = try jsonFiles(in: "cases").map { try decode(CaseStudy.self, $0) }
        #expect(Set(cases.map(\.id)) == [.ehr, .altostrat])

        let trees = try jsonFiles(in: "decisions").map { try decode(DecisionTree.self, $0) }
        let tree = try #require(trees.first)
        let rootNode = try #require(tree.node(id: tree.rootNodeID))
        #expect(rootNode.options.first?.outcome == .next(nodeID: "second"))

        let drills = try decode(KeywordDrillFile.self, root.appending(path: "drills/keywords.json")).drills
        #expect(drills.map(\.id) == ["K-0001", "K-0002"])
    }

    @Test("試験定義をデコードでき、入れ子の構造が保たれる")
    func exam() throws {
        // Arrange
        let url = root.appending(path: "exam.json")
        // Act
        let exam = try decode(Exam.self, url)
        // Assert
        #expect(exam.id == "test-alpha")
        #expect(exam.vendor == "google-cloud")
        #expect(exam.guideVersion == "6.1")
        #expect(exam.guideURL.scheme == "https")
        #expect(exam.format.officialQuestionCount.min <= exam.format.officialQuestionCount.max)
        #expect(exam.format.questionKinds == [.single, .multiple])
        #expect(exam.format.mockExam.setCount == 6)
        #expect(exam.scoring.policy == .allOrNothing)
        #expect(exam.domains.map(\.id) == Array(1...6))
        #expect(abs(exam.domains.map(\.weight).reduce(0, +) - 1.0) < 0.001)
        #expect(exam.domains.allSatisfy { !$0.subObjectives.isEmpty })
        #expect(exam.features.keywordDrills)
        #expect(exam.taxonomies.wafPillars.map(\.id) == WAFPillar.allCases)
        #expect(exam.caseStudies == [.ehr, .altostrat])
    }

    @Test("ベンダー定義をデコードでき、試験の vendor が実在する")
    func vendors() throws {
        // Arrange: vendors.json は exams/<examID>/ の 2 階層上にある
        let url = root.deletingLastPathComponent().deletingLastPathComponent().appending(path: "vendors.json")
        // Act
        let vendors = try decode(VendorsFile.self, url).vendors
        let exam = try decode(Exam.self, root.appending(path: "exam.json"))
        // Assert
        let vendor = try #require(vendors.first { $0.id == exam.vendor })
        #expect(vendor.name == "Google Cloud")
        #expect(!vendor.trademarkNotice.ja.isEmpty)
        #expect(vendor.defaultReferenceLicense == .ccBy40)
    }

    @Test("エンコードして再デコードしても同じ値になる")
    func roundTrip() throws {
        let original = try jsonFiles(in: "questions").map { try decode(Question.self, $0) }
        let data = try JSONEncoder().encode(original)
        let decoded = try decoder.decode([Question].self, from: data)
        #expect(decoded == original)
    }
}
