import DomainModels

/// Feature が依存する、読み込み済みの1試験のコンテンツ。
public protocol ExamContentProvider: Sendable {
    var definition: ExamDefinition { get }
    var vendor: Vendor { get }
    var packVersion: String { get }
    var questionIndex: [QuestionIndexEntry] { get }
    var examSets: [ExamSet] { get }
    var docsIndex: [DocEntry] { get }
    func questions(ids: [String]) async throws(ContentError) -> [Question]
    func flashcards() async throws(ContentError) -> [Flashcard]
    func caseStudies() async throws(ContentError) -> [CaseStudy]
    func decisionTrees() async throws(ContentError) -> [DecisionTree]
    func keywordDrills() async throws(ContentError) -> [KeywordDrill]
    func docBody(for entry: DocEntry) async throws(ContentError) -> String
}

public enum ContentError: Error, Equatable, Sendable {
    case fileMissing(String)
    case undecodable(path: String, reason: String)
    case featureDisabled(String)
    case unknownQuestionIDs([String])
    case integrityViolations([IntegrityViolation])
    case storage(String)
}
