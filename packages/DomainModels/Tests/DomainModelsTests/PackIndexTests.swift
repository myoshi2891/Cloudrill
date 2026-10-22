import Foundation
import Testing
@testable import DomainModels

@Suite("パックの索引")
struct PackIndexTests {
    private func decode<T: Decodable>(_ type: T.Type, _ json: String) throws -> T {
        try ContentDecoder.make().decode(type, from: Data(json.utf8))
    }

    @Test("QuestionIndexEntry: 索引の例を読める")
    func decodeIndexEntry() throws {
        let json = #"""
        {"id":"Q-3.2-0147","revision":2,"domain":3,"subObjective":"3.2","caseStudy":"ehr",
         "difficulty":3,"kind":"single","examSets":[1]}
        """#
        let entry = try decode(QuestionIndexEntry.self, json)
        #expect(entry.kind == .single)
        #expect(entry.caseStudy == "ehr")
        #expect(entry.revision == 2)
        #expect(entry.examSets == [1])
    }

    @Test("QuestionIndexEntry: caseStudy が null なら nil")
    func indexEntryWithoutCase() throws {
        let json = #"""
        {"id":"Q-1.1-0001","revision":1,"domain":1,"subObjective":"1.1","caseStudy":null,
         "difficulty":2,"kind":"multiple","examSets":[]}
        """#
        let entry = try decode(QuestionIndexEntry.self, json)
        #expect(entry.caseStudy == nil)
        #expect(entry.kind == .multiple)
    }

    @Test("QuestionIndexEntry: caseStudy のキーがなければデコードエラー(null とは区別する)")
    func missingCaseStudyKeyFails() {
        let json = #"""
        {"id":"Q-1.1-0001","revision":1,"domain":1,"subObjective":"1.1",
         "difficulty":2,"kind":"multiple","examSets":[]}
        """#
        #expect(throws: DecodingError.self) { try decode(QuestionIndexEntry.self, json) }
    }

    @Test("QuestionIndexEntry: エンコードすると nil の caseStudy は null として残り、再デコードできる")
    func indexEntryRoundTripKeepsNull() throws {
        let entry = QuestionIndexEntry(
            id: "Q-1.1-0001", revision: 1, domain: 1, subObjective: "1.1", caseStudy: nil, difficulty: 2,
            kind: .single, examSets: []
        )
        let data = try JSONEncoder().encode(entry)
        let json = try #require(String(data: data, encoding: .utf8))
        #expect(json.contains(#""caseStudy":null"#))
        #expect(try decode(QuestionIndexEntry.self, json) == entry)
    }

    @Test("QuestionIndexEntry: 未知の kind はデコードエラー(① 構造語彙)")
    func unknownKindFails() {
        let json = #"""
        {"id":"Q-1.1-0001","revision":1,"domain":1,"subObjective":"1.1","caseStudy":null,
         "difficulty":2,"kind":"ordering","examSets":[]}
        """#
        #expect(throws: DecodingError.self) { try decode(QuestionIndexEntry.self, json) }
    }

    @Test("DocEntry: フロントマターの内容と本文のパスを読める")
    func decodeDocEntry() throws {
        let json = #"""
        {"subObjective":"3.2","title":"可用性の設計","path":"docs/3.2.md",
         "references":[{"title":"Docs","url":"https://cloud.google.com/docs","license":"CC-BY-4.0"}]}
        """#
        let entry = try decode(DocEntry.self, json)
        #expect(entry.path == "docs/3.2.md")
        #expect(entry.references.map(\.license) == [.ccBy40])
    }
}
