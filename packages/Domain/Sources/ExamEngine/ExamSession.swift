import Foundation
import StudyModels

public enum SubmitReason: String, Codable, Hashable, Sendable {
    case user
    case timeExpired
}

public enum ExamSessionState: Codable, Hashable, Sendable {
    case notStarted, inProgress, reviewing, suspended
    case submitted(SubmitReason)
    case abandoned
}

public enum ExamSessionEvent: Hashable, Sendable {
    case start, suspend, resume, openReview, closeReview, submit, abandon, tick
}

public enum ExamSessionError: Error, Equatable, Sendable {
    case invalidTransition(from: ExamSessionState, event: ExamSessionEvent)
    /// 解答・フラグ・移動を、受け付けない状態で行った
    case operationNotAllowed(ExamSessionState)
    case unknownQuestion(String)
    case indexOutOfRange(Int)
}

/// 模試の状態機械(BDD 6.1、DDD-P1 3.3)。時刻は引数で受け取り、自身では取得しない。
public struct ExamSession: Hashable, Sendable {
    public private(set) var state: ExamSessionState
    public private(set) var timer: ExamTimer?
    public private(set) var answers: [String: AnswerSelection]
    public private(set) var flags: Set<String>
    public private(set) var currentIndex: Int
    public let order: QuestionOrder
    private let duration: Duration
    private let timerPolicy: ExamTimerPolicy

    public init(order: QuestionOrder, duration: Duration, timerPolicy: ExamTimerPolicy) {
        state = .notStarted
        timer = nil
        answers = [:]
        flags = []
        currentIndex = 0
        self.order = order
        self.duration = duration
        self.timerPolicy = timerPolicy
    }

    /// 遷移表(DDD-P1 3.3)。nil は許されない遷移。tick はどの状態でもエラーにしない
    /// (画面の更新タイマーが、提出の後に1回余分に発火することがあるため)。
    static func transition(from state: ExamSessionState, event: ExamSessionEvent, isExpired: Bool) -> ExamSessionState? {
        switch (state, event) {
        case (.notStarted, .start): .inProgress
        case (.inProgress, .suspend), (.reviewing, .suspend): .suspended
        case (.inProgress, .openReview): .reviewing
        case (.reviewing, .closeReview): .inProgress
        // 提出は見直し一覧からだけ行う(BDD 4.3)
        case (.reviewing, .submit): .submitted(.user)
        case (.inProgress, .tick), (.reviewing, .tick): isExpired ? .submitted(.timeExpired) : state
        case (.suspended, .resume): isExpired ? .submitted(.timeExpired) : .inProgress
        case (.suspended, .abandon): .abandoned
        case (_, .tick): state
        default: nil
        }
    }

    public mutating func handle(_ event: ExamSessionEvent, at now: Date) throws(ExamSessionError) {
        // 許されない遷移では値を変えないよう、タイマーの写しで判定してから確定する
        var nextTimer = timer
        switch event {
        case .start where state == .notStarted:
            nextTimer = ExamTimer(startedAt: now, duration: duration)
        case .suspend where timerPolicy.pausesWhileSuspended:
            nextTimer?.pause(at: now)
        case .resume:
            nextTimer?.resume(at: now)
        default:
            break
        }
        let isExpired = nextTimer?.isExpired(at: now) ?? false
        guard let next = Self.transition(from: state, event: event, isExpired: isExpired) else {
            throw .invalidTransition(from: state, event: event)
        }
        state = next
        timer = nextTimer
    }

    /// 解答を記録する。nil なら未解答に戻す。見直し中は受け付けない(問題に戻ってから変える)
    public mutating func select(_ selection: AnswerSelection?, for questionID: String) throws(ExamSessionError) {
        guard state == .inProgress else { throw .operationNotAllowed(state) }
        try requireQuestion(questionID)
        answers[questionID] = selection
    }

    public mutating func toggleFlag(for questionID: String) throws(ExamSessionError) {
        try requireNavigable()
        try requireQuestion(questionID)
        if flags.remove(questionID) == nil {
            flags.insert(questionID)
        }
    }

    public mutating func move(to index: Int) throws(ExamSessionError) {
        try requireNavigable()
        guard order.items.indices.contains(index) else { throw .indexOutOfRange(index) }
        currentIndex = index
    }

    /// 出題順の未解答の問題
    public var unansweredQuestionIDs: [String] {
        order.items.map(\.questionID).filter { answers[$0] == nil }
    }

    /// 出題順のフラグ付きの問題
    public var flaggedQuestionIDs: [String] {
        order.items.map(\.questionID).filter { flags.contains($0) }
    }

    private func requireNavigable() throws(ExamSessionError) {
        guard state == .inProgress || state == .reviewing else { throw .operationNotAllowed(state) }
    }

    private func requireQuestion(_ questionID: String) throws(ExamSessionError) {
        guard order.items.contains(where: { $0.questionID == questionID }) else { throw .unknownQuestion(questionID) }
    }

    // MARK: - 保存と復元(P3、AC-02)

    /// 保存用の値。タイマーのポリシーは設定なので含めない
    public struct Snapshot: Codable, Hashable, Sendable {
        public var state: ExamSessionState
        public var timer: ExamTimer?
        public var answers: [String: AnswerSelection]
        public var flags: Set<String>
        public var currentIndex: Int
        public var order: QuestionOrder
        public var duration: Duration
    }

    public var snapshot: Snapshot {
        Snapshot(
            state: state, timer: timer, answers: answers, flags: flags,
            currentIndex: currentIndex, order: order, duration: duration
        )
    }

    public init(snapshot: Snapshot, timerPolicy: ExamTimerPolicy) {
        state = snapshot.state
        timer = snapshot.timer
        answers = snapshot.answers
        flags = snapshot.flags
        currentIndex = snapshot.currentIndex
        order = snapshot.order
        duration = snapshot.duration
        self.timerPolicy = timerPolicy
    }
}
