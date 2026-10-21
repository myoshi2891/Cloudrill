import Foundation
import Testing
@testable import DomainModels

@Suite("カスタムデコード")
struct CustomDecodingTests {
    private func decode<T: Decodable>(_ type: T.Type, _ json: String) throws -> T {
        try ContentDecoder.make().decode(type, from: Data(json.utf8))
    }

    @Test("QuestionType: kind で分岐する(正常系)", arguments: [
        (#"{"kind":"single"}"#, QuestionType.single),
        (#"{"kind":"multiple","count":2}"#, QuestionType.multiple(count: 2)),
        (#"{"kind":"multiple","count":3}"#, QuestionType.multiple(count: 3)),
    ])
    func questionTypeValid(json: String, expected: QuestionType) throws {
        #expect(try decode(QuestionType.self, json) == expected)
    }

    @Test("QuestionType: 不正な組み合わせはエラー(異常系)", arguments: [
        #"{"kind":"single","count":2}"#,
        #"{"kind":"multiple"}"#,
        #"{"kind":"multiple","count":1}"#,
        #"{"kind":"ordering"}"#,
        #"{}"#,
    ])
    func questionTypeInvalid(json: String) {
        #expect(throws: DecodingError.self) { try decode(QuestionType.self, json) }
    }

    @Test("QuestionType: エンコード結果が Schema の形になる")
    func questionTypeEncoding() throws {
        let encoder = JSONEncoder()
        encoder.outputFormatting = .sortedKeys
        let single = String(decoding: try encoder.encode(QuestionType.single), as: UTF8.self)
        let multiple = String(decoding: try encoder.encode(QuestionType.multiple(count: 2)), as: UTF8.self)
        #expect(single == #"{"kind":"single"}"#)
        #expect(multiple == #"{"count":2,"kind":"multiple"}"#)
    }

    @Test("Choice: mistakeTags の省略は空配列になる")
    func choiceWithoutMistakeTags() throws {
        let json = #"{"id":"a","text":{"ja":"案"},"isCorrect":true,"rationale":{"ja":"理由"}}"#
        let choice = try decode(Choice.self, json)
        #expect(choice.mistakeTags.isEmpty)
        #expect(choice.text.text(preferEnglish: true) == "案")
    }

    @Test("DecisionOption: next と result はどちらか一方だけ", arguments: [
        #"{"label":{"ja":"はい"},"next":"n1","result":{"service":"GKE","rationale":{"ja":"理由"}}}"#,
        #"{"label":{"ja":"はい"}}"#,
    ])
    func decisionOptionInvalid(json: String) {
        #expect(throws: DecodingError.self) { try decode(DecisionOption.self, json) }
    }

    @Test("未知の列挙値はエラー")
    func unknownEnum() {
        #expect(throws: DecodingError.self) { try decode(MistakeTag.self, #""unknown""#) }
    }

    private func manifestJSON(examID: String? = "gcp-pca") -> String {
        let examIDField = examID.map { #""examID":"\#($0)","# } ?? ""
        return """
        {"formatVersion":1,\(examIDField)"keyID":"content-2026",
         "packVersion":"1.2.0","examGuideVersion":"6.1","minAppVersion":"1.0.0",
         "createdAt":"2026-11-01T00:00:00Z",
         "files":[{"path":"questions/domain1.json","sha256":"\(String(repeating: "a", count: 64))","size":10}]}
        """
    }

    @Test("Manifest: createdAt を ISO 8601 でデコードし、formatVersion・examID・keyID を読める")
    func manifest() throws {
        let manifest = try decode(Manifest.self, manifestJSON())
        #expect(manifest.createdAt == Date(timeIntervalSince1970: 1_793_491_200))
        #expect(manifest.files.first?.size == 10)
        #expect(manifest.formatVersion == 1)
        #expect(manifest.examID == "gcp-pca")
        #expect(manifest.keyID == "content-2026")
    }

    @Test("Manifest: examID がなければデコードエラー")
    func manifestRequiresExamID() {
        #expect {
            try decode(Manifest.self, manifestJSON(examID: nil))
        } throws: { error in
            guard case DecodingError.keyNotFound(let key, _) = error else { return false }
            return key.stringValue == "examID"
        }
    }
}
