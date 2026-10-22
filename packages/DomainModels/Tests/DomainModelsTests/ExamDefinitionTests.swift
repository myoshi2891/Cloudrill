import Foundation
import Testing
@testable import DomainModels

@Suite("試験定義")
struct ExamDefinitionTests {
    private let decoder = ContentDecoder.make()

    /// test-beta の exam.json を辞書として読む(値を変えた JSON を作るため)
    private func betaJSONObject() throws -> [String: Any] {
        let data = try Data(contentsOf: FixturePaths.examRoot("test-beta").appending(path: "exam.json"))
        return try #require(try JSONSerialization.jsonObject(with: data) as? [String: Any])
    }

    private func decode(_ object: [String: Any]) throws -> ExamDefinition {
        try decoder.decode(ExamDefinition.self, from: JSONSerialization.data(withJSONObject: object))
    }

    @Test("サブ項目 ID からドメイン番号を引ける(ドメイン番号で始まらない ID も含む)")
    func domainBySubObjective() throws {
        // Arrange / Act
        let definition = try decode(try betaJSONObject())
        // Assert
        #expect(definition.domainBySubObjective == ["1.1": 1, "1.2": 1, "NET.1": 2, "NET.2": 2, "3.1": 3, "4.1": 4])
    }

    @Test("未知の採点方式はデコードエラー(構造語彙はアプリの更新が必要)")
    func unknownScoringPolicyFails() throws {
        // Arrange
        var object = try betaJSONObject()
        object["scoring"] = ["policy": "partialCredit"]
        // Act / Assert
        #expect(throws: DecodingError.self) { try decode(object) }
    }

    @Test("機能のフラグがない古い exam.json は、その機能を無効として読む")
    func missingFeatureFlagDefaultsToFalse() throws {
        // Arrange
        var object = try betaJSONObject()
        var features = try #require(object["features"] as? [String: Any])
        features["keywordDrills"] = nil
        features["flashcards"] = true
        object["features"] = features
        // Act
        let definition = try decode(object)
        // Assert
        #expect(definition.features.keywordDrills == false)
        #expect(definition.features.flashcards)
    }

    @Test("形の違う試験(test-beta)の値を読める")
    func betaShape() throws {
        let definition = try decode(try betaJSONObject())
        #expect(definition.vendor == "example-cloud")
        #expect(definition.format.questionKinds == [.single])
        #expect(definition.format.mockExam.caseStudiesPerSet == 0)
        #expect(definition.caseStudies.isEmpty)
        #expect(definition.taxonomies.wafPillars.map(\.id) == ["resilience", "efficiency", "governance"])
    }
}
