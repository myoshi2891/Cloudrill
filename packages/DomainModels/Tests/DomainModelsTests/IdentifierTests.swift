import Foundation
import Testing
@testable import DomainModels

@Suite("文字列 ID")
struct IdentifierTests {
    private func decode<T: Decodable>(_ type: T.Type, _ json: String) throws -> T {
        try ContentDecoder.make().decode(type, from: Data(json.utf8))
    }

    @Test("文字列からデコードできる(試験語彙は列挙で固定しない)")
    func decodeFromString() throws {
        #expect(try decode(CaseStudyID.self, #""ehr""#) == CaseStudyID(rawValue: "ehr"))
        #expect(try decode(CaseStudyID.self, #""acmeBank""#).rawValue == "acmeBank")
        #expect(try decode(WAFPillarID.self, #""resilience""#).rawValue == "resilience")
    }

    @Test("空文字はデコードエラー")
    func rejectEmpty() {
        expectDataCorrupted(ExamID.self)
        expectDataCorrupted(VendorID.self)
        expectDataCorrupted(CaseStudyID.self)
        expectDataCorrupted(WAFPillarID.self)
    }

    private func expectDataCorrupted<T: StringIdentifier>(_ type: T.Type) {
        #expect {
            try decode(type, #""""#)
        } throws: { error in
            guard case DecodingError.dataCorrupted = error else { return false }
            return true
        }
    }

    @Test("エンコード結果はオブジェクトではなく文字列")
    func encodeAsPlainString() throws {
        // Arrange
        let id: ExamID = "gcp-pca"
        // Act
        let json = try #require(String(data: try JSONEncoder().encode(id), encoding: .utf8))
        // Assert
        #expect(json == #""gcp-pca""#)
        #expect(id.description == "gcp-pca")
    }

    @Test("試験が異なれば、同じ ID でも等しくない")
    func examScopedEquality() {
        let alpha = ExamScoped(examID: "test-alpha", id: "Q-1.1-0001")
        let beta = ExamScoped(examID: "test-beta", id: "Q-1.1-0001")
        #expect(alpha != beta)
        #expect(alpha == ExamScoped(examID: "test-alpha", id: "Q-1.1-0001"))
    }

    @Test("rawValue の辞書順で並ぶ")
    func comparable() {
        let ids: [CaseStudyID] = ["cymbal", "altostrat", "ehr"]
        #expect(ids.sorted().map(\.rawValue) == ["altostrat", "cymbal", "ehr"])
    }
}
