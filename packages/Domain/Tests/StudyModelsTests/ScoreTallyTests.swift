import Testing
import StudyModels

@Suite("ScoreTally")
struct ScoreTallyTests {
    @Test("出題数が 0 なら ratio は nil(0% と区別する)")
    func ratioIsNilWhenEmpty() {
        // Arrange
        let tally = ScoreTally(correct: 0, total: 0)
        // Act / Assert
        #expect(tally.ratio == nil)
    }

    @Test("正答率")
    func ratio() {
        // Arrange
        let tally = ScoreTally(correct: 3, total: 4)
        // Act / Assert
        #expect(tally.ratio == 0.75)
    }
}
