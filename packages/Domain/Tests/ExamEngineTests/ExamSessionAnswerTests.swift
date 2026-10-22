import Foundation
import Testing
import StudyModels
@testable import ExamEngine

@Suite("ExamSession の解答")
struct ExamSessionAnswerTests {
    private let now = Date(timeIntervalSince1970: 1_793_527_200)  // 2026-11-01T10:00:00Z

    private func startedSession(count: Int = 3) throws -> ExamSession {
        var session = ExamSession(order: makeOrder(count: count), duration: .seconds(90 * 60), timerPolicy: ExamTimerPolicy())
        try session.handle(.start, at: now)
        return session
    }

    @Test("解答中に選ぶと記録される")
    func selectRecordsAnswer() throws {
        // Arrange
        var session = try startedSession()
        // Act
        try session.select(.choices(["a"]), for: "Q1")
        // Assert
        #expect(session.answers["Q1"] == .choices(["a"]))
    }

    @Test("nil を選ぶと未解答に戻る")
    func selectNilClearsAnswer() throws {
        // Arrange
        var session = try startedSession()
        try session.select(.choices(["a"]), for: "Q1")
        // Act
        try session.select(nil, for: "Q1")
        // Assert
        #expect(session.answers["Q1"] == nil)
        #expect(session.unansweredQuestionIDs.contains("Q1"))
    }

    @Test("空の選択は未解答として扱う(複数選択で最後の選択肢を外した場合など)")
    func selectEmptyClearsAnswer() throws {
        // Arrange
        var session = try startedSession()
        try session.select(.choices(["a"]), for: "Q1")
        try session.select(.choices(["b"]), for: "Q2")
        // Act
        try session.select(.choices([]), for: "Q1")
        // Assert
        #expect(session.answers["Q1"] == nil)
        #expect(session.answers["Q2"] == .choices(["b"]))
        #expect(session.unansweredQuestionIDs == ["Q1", "Q3"])
    }

    @Test("見直し中は解答を変えられない(問題に戻ってから変える)")
    func selectOnlyInProgress() throws {
        // Arrange
        var session = try startedSession()
        try session.handle(.openReview, at: now)
        // Act / Assert
        #expect(throws: ExamSessionError.operationNotAllowed(.reviewing)) {
            try session.select(.choices(["a"]), for: "Q1")
        }
    }

    @Test("出題順にない問題 ID はエラー")
    func selectUnknownQuestion() throws {
        // Arrange
        var session = try startedSession()
        // Act / Assert
        #expect(throws: ExamSessionError.unknownQuestion("Q99")) {
            try session.select(.choices(["a"]), for: "Q99")
        }
        #expect(throws: ExamSessionError.unknownQuestion("Q99")) {
            try session.toggleFlag(for: "Q99")
        }
    }

    @Test("フラグは切り替えるたびに付け外しされる")
    func toggleFlag() throws {
        // Arrange
        var session = try startedSession()
        // Act / Assert
        try session.toggleFlag(for: "Q1")
        #expect(session.flags == ["Q1"])
        try session.toggleFlag(for: "Q1")
        #expect(session.flags.isEmpty)
    }

    @Test("範囲外の位置には移動できない", arguments: [40, 45, -1])
    func moveClampsIndex(index: Int) throws {
        // Arrange
        var session = try startedSession(count: 40)
        // Act / Assert
        #expect(throws: ExamSessionError.indexOutOfRange(index)) {
            try session.move(to: index)
        }
        #expect(session.currentIndex == 0)
    }

    @Test("見直し一覧の未解答とフラグ(出題順に並ぶ)")
    func reviewSummary() throws {
        // Arrange
        var session = try startedSession(count: 40)
        for number in 1...30 {
            try session.select(.choices(["a"]), for: "Q\(number)")
        }
        for number in [5, 35, 2] {
            try session.toggleFlag(for: "Q\(number)")
        }
        // Act
        try session.handle(.openReview, at: now)
        // Assert
        #expect(session.unansweredQuestionIDs.count == 10)
        #expect(session.unansweredQuestionIDs.first == "Q31")
        #expect(session.flaggedQuestionIDs == ["Q2", "Q5", "Q35"])
    }

    @Test("Snapshot に変換して復元すると元の値に戻る(JSON を経由しても同じ)")
    func restoreFromSnapshot() throws {
        // Arrange
        let policy = ExamTimerPolicy(pausesWhileSuspended: true)
        var session = ExamSession(order: makeOrder(count: 5), duration: .seconds(90 * 60), timerPolicy: policy)
        try session.handle(.start, at: now)
        try session.select(.choices(["b"]), for: "Q2")
        try session.toggleFlag(for: "Q3")
        try session.move(to: 3)
        try session.handle(.suspend, at: now.addingTimeInterval(600))
        // Act
        let data = try JSONEncoder().encode(session.snapshot)
        let restored = ExamSession(snapshot: try JSONDecoder().decode(ExamSession.Snapshot.self, from: data), timerPolicy: policy)
        // Assert
        #expect(restored == session)
        #expect(restored.timer?.pausedRemaining == .seconds(80 * 60))
    }

    @Test("Snapshot の位置が範囲外なら出題順の範囲に丸めて復元する", arguments: [(5, 99, 4), (5, -3, 0), (0, 2, 0)])
    func restoreClampsIndex(count: Int, savedIndex: Int, expected: Int) {
        // Arrange
        let order = count == 0 ? QuestionOrder(items: []) : makeOrder(count: count)
        var snapshot = ExamSession(order: order, duration: .seconds(90 * 60), timerPolicy: ExamTimerPolicy()).snapshot
        snapshot.currentIndex = savedIndex
        // Act
        let restored = ExamSession(snapshot: snapshot, timerPolicy: ExamTimerPolicy())
        // Assert
        #expect(restored.currentIndex == expected)
    }
}
