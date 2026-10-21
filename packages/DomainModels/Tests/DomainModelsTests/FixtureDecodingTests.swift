import Foundation
import Testing
@testable import DomainModels

/// content/tests/fixtures/valid を JSON に変換したもの(content/scripts/export_json.py で生成)の場所。
enum FixturePaths {
    /// valid-json/(このファイル packages/DomainModels/Tests/DomainModelsTests/ から見て ../../../../content/…)
    static let validJSON: URL = URL(filePath: #filePath)
        .deletingLastPathComponent()
        .deletingLastPathComponent()
        .deletingLastPathComponent()
        .appending(path: "../../content/tests/fixtures/valid-json")
        .standardized

    /// valid-json/exams/ の直下の試験 ID(名前順)
    static let examIDs: [String] = {
        let exams = validJSON.appending(path: "exams")
        let names = (try? FileManager.default.contentsOfDirectory(atPath: exams.path)) ?? []
        return names.filter { !$0.hasPrefix(".") }.sorted()
    }()

    static func examRoot(_ examID: String) -> URL {
        validJSON.appending(path: "exams/\(examID)")
    }

    static func jsonFiles(under base: URL) -> [URL] {
        guard let enumerator = FileManager.default.enumerator(at: base, includingPropertiesForKeys: nil) else { return [] }
        return enumerator
            .compactMap { $0 as? URL }
            .filter { $0.pathExtension == "json" }
            .sorted { $0.path < $1.path }
    }
}

/// valid fixture の JSON をデコードできること。
@Suite("valid fixture のデコード")
struct FixtureDecodingTests {
    /// 試験固有の値を確かめるテストは、PCA と同じ形の test-alpha を使う
    let root: URL
    let decoder = ContentDecoder.make()

    init() throws {
        root = FixturePaths.examRoot("test-alpha")
        let exists = FileManager.default.fileExists(atPath: root.appending(path: "exam-sets.json").path)
        try #require(exists, "フィクスチャがありません: \(root.path)。content/scripts/export_json.py を実行してください")
    }

    private func jsonFiles(in directory: String) throws -> [URL] {
        FixturePaths.jsonFiles(under: root.appending(path: directory))
    }

    private func decode<T: Decodable>(_ type: T.Type, _ url: URL) throws -> T {
        try decoder.decode(type, from: Data(contentsOf: url))
    }

    /// 試験ディレクトリのファイルを、置き場所に応じた型でデコードする
    private func decodeExamFile(_ url: URL, examRoot: URL) throws {
        let relative = url.path.replacingOccurrences(of: examRoot.path + "/", with: "")
        switch relative.split(separator: "/").first.map(String.init) {
        case "exam.json": _ = try decode(ExamDefinition.self, url)
        case "exam-sets.json": _ = try decode(ExamSetsFile.self, url)
        case "questions": _ = try decode(Question.self, url)
        case "flashcards": _ = try decode(FlashcardFile.self, url)
        case "cases": _ = try decode(CaseStudy.self, url)
        case "decisions": _ = try decode(DecisionTree.self, url)
        case "drills": _ = try decode(KeywordDrillFile.self, url)
        default: Issue.record("対応する型がないファイル: \(relative)")
        }
    }

    @Test("valid-json に形の違う 2 つの試験がある")
    func examDirectories() {
        #expect(FixturePaths.examIDs == ["test-alpha", "test-beta"])
    }

    @Test("試験ごとに、すべてのファイルをデコードできる", arguments: FixturePaths.examIDs)
    func allFilesDecode(examID: String) throws {
        // Arrange
        let examRoot = FixturePaths.examRoot(examID)
        let files = FixturePaths.jsonFiles(under: examRoot)
        try #require(!files.isEmpty)
        // Act / Assert
        for file in files {
            #expect(throws: Never.self, "\(file.lastPathComponent)") { try decodeExamFile(file, examRoot: examRoot) }
        }
    }

    @Test("exam.json の id がディレクトリ名と等しい", arguments: FixturePaths.examIDs)
    func examDefinitionMatchesDirectory(examID: String) throws {
        let definition = try decode(ExamDefinition.self, FixturePaths.examRoot(examID).appending(path: "exam.json"))
        #expect(definition.id.rawValue == examID)
    }

    @Test("vendors.json に 2 つのベンダーがある")
    func vendorsDecode() throws {
        let vendors = try decode(VendorsFile.self, FixturePaths.validJSON.appending(path: "vendors.json")).vendors
        #expect(Set(vendors.map(\.id)).isSuperset(of: ["google-cloud", "example-cloud"]))
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
        #expect(set1.caseStudies == ["ehr", "altostrat"])
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

    @Test("フラッシュカード・ケース・ツリー・ドリルをデコードできる")
    func otherContent() throws {
        let cards = try jsonFiles(in: "flashcards").flatMap { try decode(FlashcardFile.self, $0).cards }
        #expect(cards.count == 2)

        let cases = try jsonFiles(in: "cases").map { try decode(CaseStudy.self, $0) }
        #expect(Set(cases.map(\.id)) == ["ehr", "altostrat"])

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
        let exam = try decode(ExamDefinition.self, url)
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
        #expect(exam.taxonomies.wafPillars.map(\.id) == [
            "operationalExcellence", "security", "reliability", "costOptimization", "performance", "sustainability",
        ])
        #expect(exam.caseStudies == ["ehr", "altostrat"])
    }

    @Test("ベンダー定義をデコードでき、試験の vendor が実在する")
    func vendors() throws {
        // Arrange
        let url = FixturePaths.validJSON.appending(path: "vendors.json")
        // Act
        let vendors = try decode(VendorsFile.self, url).vendors
        let exam = try decode(ExamDefinition.self, root.appending(path: "exam.json"))
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
