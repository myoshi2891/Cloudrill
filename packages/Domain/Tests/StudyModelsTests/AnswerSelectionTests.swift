import Foundation
import Testing
import StudyModels

@Suite("AnswerSelection")
struct AnswerSelectionTests {
    @Test("choiceIDs を昇順に並べて出力する")
    func encodesSortedChoiceIDs() throws {
        // Arrange
        let encoder = JSONEncoder()
        encoder.outputFormatting = .sortedKeys
        // Act
        let json = try encoder.encode(AnswerSelection.choices(["c", "a"]))
        // Assert
        #expect(String(data: json, encoding: .utf8) == #"{"choiceIDs":["a","c"],"kind":"choices"}"#)
    }

    @Test("エンコードしてデコードすると元の値に戻る")
    func roundTrip() throws {
        // Arrange
        let selection = AnswerSelection.choices(["b", "d"])
        // Act
        let decoded = try JSONDecoder().decode(AnswerSelection.self, from: JSONEncoder().encode(selection))
        // Assert
        #expect(decoded == selection)
    }

    @Test("未知の kind はデコードエラー(出題形式の追加はアプリの更新が必要)")
    func unknownKindFails() {
        // Arrange
        let json = Data(#"{"kind":"ordering"}"#.utf8)
        // Act / Assert
        #expect(throws: DecodingError.self) {
            try JSONDecoder().decode(AnswerSelection.self, from: json)
        }
    }
}
