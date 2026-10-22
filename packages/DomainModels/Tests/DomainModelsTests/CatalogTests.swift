import Foundation
import Testing
@testable import DomainModels

@Suite("カタログ")
struct CatalogTests {
    private func decode(_ json: String) throws -> Catalog {
        try ContentDecoder.make().decode(Catalog.self, from: Data(json.utf8))
    }

    private func catalogJSON(status: String, latestPackVersion: String = #""1.2.0""#) -> String {
        #"""
        {"formatVersion":1,"generatedAt":"2026-11-01T00:00:00Z","exams":[
          {"id":"gcp-pca","vendor":"google-cloud",
           "name":{"ja":"Google Cloud Professional Cloud Architect","en":"Google Cloud Professional Cloud Architect"},
           "shortName":"PCA","status":"\#(status)","latestPackVersion":\#(latestPackVersion),"minAppVersion":"1.0.0",
           "productIDs":[]}]}
        """#
    }

    @Test("DDD 4.8 の例を読める")
    func decodeCatalog() throws {
        let catalog = try decode(catalogJSON(status: "available"))
        #expect(catalog.exams[0].status == .available)
        #expect(catalog.exams[0].id == "gcp-pca")
        #expect(catalog.exams[0].latestPackVersion == "1.2.0")
        #expect(catalog.generatedAt == Date(timeIntervalSince1970: 1_793_491_200))
    }

    @Test("パックがまだない試験は latestPackVersion が nil")
    func unreleasedExam() throws {
        let catalog = try decode(catalogJSON(status: "comingSoon", latestPackVersion: "null"))
        #expect(catalog.exams[0].status == .comingSoon)
        #expect(catalog.exams[0].latestPackVersion == nil)
    }

    @Test("latestPackVersion・minAppVersion のキーがなければデコードエラー(null とは区別する)", arguments: [
        #""latestPackVersion":"1.2.0","#, #""minAppVersion":"1.0.0","#,
    ])
    func missingVersionKeyFails(removed: String) {
        let json = catalogJSON(status: "available").replacingOccurrences(of: removed, with: "")
        #expect(throws: DecodingError.self) { try decode(json) }
    }

    @Test("エンコードすると nil の版は null として残り、再デコードできる")
    func roundTripKeepsNull() throws {
        let catalog = try decode(catalogJSON(status: "comingSoon", latestPackVersion: "null"))
        let data = try JSONEncoder().encode(catalog.exams[0])
        let json = try #require(String(data: data, encoding: .utf8))
        #expect(json.contains(#""latestPackVersion":null"#))
        #expect(try JSONDecoder().decode(CatalogEntry.self, from: data) == catalog.exams[0])
    }

    @Test("未知の status はデコードエラー(① 構造語彙)")
    func unknownStatusFails() {
        #expect(throws: DecodingError.self) { try decode(catalogJSON(status: "beta")) }
    }
}
