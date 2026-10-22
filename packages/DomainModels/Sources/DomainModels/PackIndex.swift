import Foundation

/// pack-question-index.schema.json(パックの questions/index.json の1件)。
/// 起動時に読む問題の要約で、本文と選択肢は持たない(NFR-01)。
/// 共通の項目は、`Question` の同名の項目と同じ型・同じ意味にする。
public struct QuestionIndexEntry: Codable, Hashable, Sendable, Identifiable {
    /// `Question.id`
    public var id: String
    /// `Question.revision`
    public var revision: Int
    /// `Question.domain`
    public var domain: Int
    /// `Question.subObjective`
    public var subObjective: String
    /// `Question.caseStudy`。ケース問題でなければ nil(JSON では null)
    public var caseStudy: CaseStudyID?
    /// `Question.difficulty`
    public var difficulty: Int
    /// `Question.type.kind`(索引は選択数を持たない)
    public var kind: QuestionKind
    /// `Question.examSets`
    public var examSets: [Int]

    public init(
        id: String, revision: Int, domain: Int, subObjective: String, caseStudy: CaseStudyID?, difficulty: Int,
        kind: QuestionKind, examSets: [Int]
    ) {
        self.id = id
        self.revision = revision
        self.domain = domain
        self.subObjective = subObjective
        self.caseStudy = caseStudy
        self.difficulty = difficulty
        self.kind = kind
        self.examSets = examSets
    }
}

/// pack-docs-index.schema.json(パックの docs/index.json の1件)。
/// subObjective・title・references は docs/*.md のフロントマター(docs-frontmatter.schema.json)。
public struct DocEntry: Codable, Hashable, Sendable {
    public var subObjective: String
    public var title: String
    public var references: [Reference]
    /// フロントマターを除いた本文の、パック内の相対パス(docs/<subObjective>.md)
    public var path: String
}
