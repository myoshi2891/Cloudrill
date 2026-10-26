import Foundation
import DomainModels
import DomainInterfaces

/// 索引は不変の値。問題本文は actor でドメインごとにキャッシュする。
public final class PackContent: ExamContentProvider {
    public let definition: ExamDefinition
    public let vendor: Vendor
    public let packVersion: String
    public let questionIndex: [QuestionIndexEntry]
    public let examSets: [ExamSet]
    public let docsIndex: [DocEntry]
    private let files: PackFiles
    private let bodies: QuestionBodyCache

    init(definition: ExamDefinition, vendor: Vendor, packVersion: String, questionIndex: [QuestionIndexEntry], examSets: [ExamSet], docsIndex: [DocEntry], files: PackFiles) {
        self.definition = definition
        self.vendor = vendor
        self.packVersion = packVersion
        self.questionIndex = questionIndex
        self.examSets = examSets
        self.docsIndex = docsIndex
        self.files = files
        bodies = QuestionBodyCache(index: questionIndex, files: files)
    }
    public func questions(ids: [String]) async throws(ContentError) -> [Question] { try await bodies.questions(ids: ids) }
    public func flashcards() async throws(ContentError) -> [Flashcard] {
        guard definition.features.flashcards else { throw .featureDisabled("flashcards") }
        return try files.decode(FlashcardFile.self, "flashcards.json").cards
    }
    public func caseStudies() async throws(ContentError) -> [CaseStudy] {
        guard definition.features.caseStudies else { throw .featureDisabled("caseStudies") }
        return try files.decode([CaseStudy].self, "cases.json")
    }
    public func decisionTrees() async throws(ContentError) -> [DecisionTree] {
        guard definition.features.decisionTrees else { throw .featureDisabled("decisionTrees") }
        return try files.decode([DecisionTree].self, "decisions.json")
    }
    public func keywordDrills() async throws(ContentError) -> [KeywordDrill] {
        guard definition.features.keywordDrills else { throw .featureDisabled("keywordDrills") }
        return try files.decode(KeywordDrillFile.self, "drills.json").drills
    }
    public func docBody(for entry: DocEntry) async throws(ContentError) -> String {
        guard definition.features.docs else { throw .featureDisabled("docs") }
        guard docsIndex.contains(entry) else { throw .fileMissing(entry.path) }
        let raw = try files.data(entry.path)
        guard let body = String(data: raw, encoding: .utf8) else { throw .undecodable(path: entry.path, reason: "invalid UTF-8") }
        return body
    }
}
