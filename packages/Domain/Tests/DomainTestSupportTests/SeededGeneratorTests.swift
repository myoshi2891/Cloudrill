import Testing
import DomainTestSupport

@Suite("SeededGenerator")
struct SeededGeneratorTests {
    @Test("同じ seed なら同じ列を返す")
    func sameSeedSameSequence() {
        // Arrange
        var first = SeededGenerator(seed: 42)
        var second = SeededGenerator(seed: 42)
        // Act
        let firstValues = (0..<100).map { _ in first.next() }
        let secondValues = (0..<100).map { _ in second.next() }
        // Assert
        #expect(firstValues == secondValues)
    }

    @Test("SplitMix64 の参照実装と同じ値を返す")
    func matchesSplitMix64Reference() {
        // Arrange
        var generator = SeededGenerator(seed: 0)
        // Act
        let value = generator.next()
        // Assert
        #expect(value == 0xE220_A839_7B1D_CDAF)
    }

    @Test("seed が異なれば最初の値が異なる")
    func differentSeedsDiffer() {
        // Arrange
        var first = SeededGenerator(seed: 1)
        var second = SeededGenerator(seed: 2)
        // Act / Assert
        #expect(first.next() != second.next())
    }
}
