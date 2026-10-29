import Foundation
import Observation

public struct ExamReviewItem: Equatable, Sendable, Identifiable {
    public let id: String
    public let index: Int
    public var number: Int { index + 1 }
    public let isUnanswered: Bool
    public let isFlagged: Bool
}
public struct ExamSubmissionConfirmation: Equatable, Sendable {
    public let unansweredCount: Int
    public let flaggedCount: Int
}
public struct ExamReviewViewState: Sendable {
    public var items: [ExamReviewItem] = []
    public var unansweredCount: Int { items.filter(\.isUnanswered).count }
    public var flaggedCount: Int { items.filter(\.isFlagged).count }
    public var confirmation: ExamSubmissionConfirmation?
    public var isBusy = false
    public var canSubmit = false
    public var alert: String?
}

@MainActor @Observable public final class ExamReviewViewModel {
    public let session: ExamSessionViewModel
    private var confirmation: ExamSubmissionConfirmation?
    public init(session: ExamSessionViewModel) { self.session = session }
    public var state: ExamReviewViewState {
        var value = ExamReviewViewState()
        let controller = session.controller
        value.isBusy = controller.isBusy; value.alert = controller.alert
        guard let snapshot = controller.session else { return value }
        value.items = snapshot.order.items.enumerated().map { index, item in
            ExamReviewItem(id: item.questionID, index: index, isUnanswered: snapshot.answers[item.questionID] == nil,
                           isFlagged: snapshot.flags.contains(item.questionID))
        }
        value.canSubmit = snapshot.state == .reviewing && !controller.isBusy
        value.confirmation = snapshot.state == .reviewing ? confirmation : nil
        return value
    }
    public func load() async {
        await session.load()
        await session.scenePhaseChanged(isActive: true)
        await session.openReview()
    }
    public func jumpToQuestion(index: Int) async {
        confirmation = nil
        await session.returnToQuestion(index: index)
    }
    public func submitTapped() {
        guard state.canSubmit else { return }
        confirmation = ExamSubmissionConfirmation(unansweredCount: state.unansweredCount, flaggedCount: state.flaggedCount)
    }
    public func cancelSubmit() { confirmation = nil }
    public func confirmSubmit() async {
        guard confirmation != nil, state.canSubmit else { return }
        confirmation = nil
        await session.confirmSubmit()
    }
    public func retry() async { await load() }
}
