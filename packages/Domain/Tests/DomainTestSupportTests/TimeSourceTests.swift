import Foundation
import Testing
import DomainTestSupport
import StudyModels

private let start = Date(timeIntervalSince1970: 1_793_491_200)  // 2026-11-01T00:00:00Z

@Suite("ManualTimeSource")
struct ManualTimeSourceTests {
    @Test("advance(by:) で指定した時間だけ進む")
    func advance() {
        // Arrange
        let source = ManualTimeSource(start)
        // Act
        source.advance(by: .seconds(90))
        // Assert
        #expect(source.now() == ISO8601DateFormatter().date(from: "2026-11-01T00:01:30Z"))
    }
}

@Suite("FixedTimeSource")
struct FixedTimeSourceTests {
    @Test("常に同じ時刻を返す")
    func returnsFixedDate() {
        // Arrange
        let source = FixedTimeSource(start)
        // Act / Assert
        #expect(source.now() == start)
        #expect(source.now() == start)
    }
}

@Suite("SystemTimeSource")
struct SystemTimeSourceTests {
    @Test("現在時刻を返す")
    func isCloseToDate() {
        // Arrange
        let source = SystemTimeSource()
        // Act
        let difference = abs(source.now().timeIntervalSince(Date()))
        // Assert
        #expect(difference < 1)
    }
}

@Suite("Duration.timeInterval")
struct DurationTimeIntervalTests {
    @Test("秒の Double に変換する(秒未満を含む)", arguments: [
        (Duration.seconds(90), 90.0),
        (Duration.milliseconds(1500), 1.5),
        (Duration.zero, 0.0),
    ])
    func converts(duration: Duration, expected: Double) {
        // Act / Assert
        #expect(approximatelyEqual(duration.timeInterval, expected))
    }
}

@Suite("approximatelyEqual")
struct ApproximatelyEqualTests {
    @Test("許容誤差の内側と外側", arguments: [
        (0.1 + 0.2, 0.3, true),
        (1.0, 1.0 + 1e-6, false),
    ])
    func tolerance(lhs: Double, rhs: Double, expected: Bool) {
        // Act / Assert
        #expect(approximatelyEqual(lhs, rhs) == expected)
    }
}
