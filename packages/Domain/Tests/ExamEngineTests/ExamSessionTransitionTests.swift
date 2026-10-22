import Foundation
import Testing
import DomainTestSupport
import StudyModels
@testable import ExamEngine

/// 遷移表の1マス。期限内と期限切れの両方で期待を持つ(nil は invalidTransition)
struct TransitionCell: Sendable, CustomTestStringConvertible {
    var state: ExamSessionState
    var event: ExamSessionEvent
    var inTime: ExamSessionState?
    var expired: ExamSessionState?

    var testDescription: String { "\(state) + \(event)" }
}

private let n = ExamSessionState.notStarted
private let p = ExamSessionState.inProgress
private let r = ExamSessionState.reviewing
private let s = ExamSessionState.suspended
private let byUser = ExamSessionState.submitted(.user)
private let byTime = ExamSessionState.submitted(.timeExpired)
private let a = ExamSessionState.abandoned

/// 各行の並びは表の列(start, suspend, resume, openReview, closeReview, submit, abandon, tick)と同じ
private func row(_ state: ExamSessionState, _ cells: [(ExamSessionState?, ExamSessionState?)]) -> [TransitionCell] {
    let events: [ExamSessionEvent] = [.start, .suspend, .resume, .openReview, .closeReview, .submit, .abandon, .tick]
    return zip(events, cells).map { TransitionCell(state: state, event: $0, inTime: $1.0, expired: $1.1) }
}

/// 同じ期待を期限内・期限切れの両方に使う
private func same(_ state: ExamSessionState?) -> (ExamSessionState?, ExamSessionState?) { (state, state) }

/// DDD-P1 3.3 の遷移表(6 状態 × 8 イベント = 48 マス)
private let transitionCells: [TransitionCell] =
    row(n, [same(p), same(nil), same(nil), same(nil), same(nil), same(nil), same(nil), same(n)])
    + row(p, [same(nil), same(s), same(nil), same(r), same(nil), same(nil), same(nil), (p, byTime)])
    + row(r, [same(nil), same(s), same(nil), same(nil), same(p), same(byUser), same(nil), (r, byTime)])
    + row(s, [same(nil), same(nil), (p, byTime), same(nil), same(nil), same(nil), same(a), same(s)])
    + row(byUser, [same(nil), same(nil), same(nil), same(nil), same(nil), same(nil), same(nil), same(byUser)])
    + row(a, [same(nil), same(nil), same(nil), same(nil), same(nil), same(nil), same(nil), same(a)])

@Suite("ExamSession の遷移")
struct ExamSessionTransitionTests {
    private static let start = Date(timeIntervalSince1970: 1_793_527_200)  // 2026-11-01T10:00:00Z

    /// 指定した状態のセッションを、notStarted からイベントを送って作る
    private func session(in state: ExamSessionState, clock: ManualTimeSource) throws -> ExamSession {
        var session = ExamSession(order: makeOrder(count: 3), duration: .seconds(90 * 60), timerPolicy: ExamTimerPolicy())
        let events: [ExamSessionEvent] = switch state {
        case .notStarted: []
        case .inProgress: [.start]
        case .reviewing: [.start, .openReview]
        case .suspended: [.start, .suspend]
        case .submitted: [.start, .openReview, .submit]
        case .abandoned: [.start, .suspend, .abandon]
        }
        for event in events {
            try session.handle(event, at: clock.now())
        }
        #expect(session.state == state)
        return session
    }

    private func apply(_ cell: TransitionCell, expired: Bool) throws {
        // Arrange
        let clock = ManualTimeSource(Self.start)
        var session = try session(in: cell.state, clock: clock)
        clock.advance(by: expired ? .seconds(2 * 60 * 60) : .seconds(60))
        let expected = expired ? cell.expired : cell.inTime
        // Act / Assert
        guard let expected else {
            #expect(throws: ExamSessionError.invalidTransition(from: cell.state, event: cell.event)) {
                try session.handle(cell.event, at: clock.now())
            }
            return
        }
        try session.handle(cell.event, at: clock.now())
        #expect(session.state == expected)
    }

    @Test("遷移表のとおりに状態が変わる(× は invalidTransition)", arguments: transitionCells)
    func transitionTable(cell: TransitionCell) throws {
        try apply(cell, expired: false)
        try apply(cell, expired: true)
    }

    @Test("遷移表は 48 マス")
    func transitionTableHasAllCells() {
        #expect(transitionCells.count == 48)
        #expect(Set(transitionCells.map { "\($0.state)/\($0.event)" }).count == 48)
    }

    @Test("開始時に期限を決める(90 分の試験を 10:00 に開始すると 11:30)")
    func startSetsDeadline() throws {
        // Arrange
        var session = ExamSession(order: makeOrder(count: 3), duration: .seconds(90 * 60), timerPolicy: ExamTimerPolicy())
        // Act
        try session.handle(.start, at: Self.start)
        // Assert
        #expect(session.timer?.deadline == ISO8601DateFormatter().date(from: "2026-11-01T11:30:00Z"))
    }

    @Test("× の遷移では、タイマーも変わらない")
    func invalidTransitionKeepsTimer() throws {
        // Arrange
        let policy = ExamTimerPolicy(pausesWhileSuspended: true)
        var session = ExamSession(order: makeOrder(count: 3), duration: .seconds(90 * 60), timerPolicy: policy)
        try session.handle(.start, at: Self.start)
        try session.handle(.suspend, at: Self.start)
        let before = session
        // Act
        #expect(throws: ExamSessionError.self) {
            try session.handle(.suspend, at: Self.start.addingTimeInterval(60))
        }
        // Assert
        #expect(session == before)
    }
}

/// テスト用の出題順(Q1〜Qn)
func makeOrder(count: Int) -> QuestionOrder {
    QuestionOrder(items: (1...count).map { QuestionOrder.Item(questionID: "Q\($0)", choiceIDs: ["a", "b", "c", "d"]) })
}
