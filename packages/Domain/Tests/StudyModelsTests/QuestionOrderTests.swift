import Foundation
import Testing
import StudyModels

@Suite("QuestionOrder")
struct QuestionOrderTests {
    @Test("エンコードしてデコードすると元の値に戻る")
    func roundTrip() throws {
        // Arrange
        let order = QuestionOrder(items: [
            .init(questionID: "Q-1.1-0001", choiceIDs: ["c", "a", "d", "b"]),
            .init(questionID: "Q-2.1-0003", choiceIDs: ["b", "e", "a", "d", "c"]),
        ])
        // Act
        let decoded = try QuestionOrder.decode(from: JSONEncoder().encode(order))
        // Assert
        #expect(decoded == order)
        #expect(decoded.version == QuestionOrder.currentVersion)
    }

    @Test("未来の版はエラー(古いアプリで新しい形式を読まない)")
    func rejectsFutureVersion() {
        // Arrange
        let json = Data(#"{"version":2,"items":[]}"#.utf8)
        // Act
        let result = Result { () throws(QuestionOrderError) in try QuestionOrder.decode(from: json) }
        // Assert
        guard case .failure(.unsupportedVersion(2)) = result else {
            Issue.record("unsupportedVersion(2) を期待したが \(result)")
            return
        }
    }

    @Test("入れ子のデコードでも未来の版はエラー(Snapshot の復元で版の確認を素通りしない)")
    func rejectsFutureVersionWhenNested() {
        // Arrange
        struct Wrapper: Decodable { var order: QuestionOrder }
        let json = Data(#"{"order":{"version":2,"items":[]}}"#.utf8)
        // Act
        let result = Result { try JSONDecoder().decode(Wrapper.self, from: json) }
        // Assert
        guard case .failure(let error) = result, case .unsupportedVersion(2) = error as? QuestionOrderError else {
            Issue.record("unsupportedVersion(2) を期待したが \(result)")
            return
        }
    }

    @Test("壊れた JSON はエラー(元のエラーを保持する)")
    func rejectsCorruptedData() {
        // Arrange
        let json = Data(#"{"version":1}"#.utf8)
        // Act
        let result = Result { () throws(QuestionOrderError) in try QuestionOrder.decode(from: json) }
        // Assert
        guard case .failure(.invalidData(let underlying)) = result else {
            Issue.record("invalidData を期待したが \(result)")
            return
        }
        #expect(underlying is DecodingError)
    }
}
