import SwiftUI
import DesignSystem

public struct ExamReviewView: View {
    @State private var model: ExamReviewViewModel
    @State private var timelineStart = Date()
    @Environment(\.scenePhase) private var scenePhase

    public init(session: ExamSessionViewModel) {
        _model = State(initialValue: ExamReviewViewModel(session: session))
    }
    public var body: some View {
        let state = model.state
        List {
            Section {
                TimelineView(.periodic(from: timelineStart, by: 1)) { context in
                    TimerLabel(remainingSeconds: model.session.state.remainingSeconds)
                        .task(id: Int(context.date.timeIntervalSince1970)) { await model.session.tick() }
                }
                Text(counts(unanswered: state.unansweredCount, flagged: state.flaggedCount))
                    .accessibilityIdentifier("review-counts")
                Button { model.submitTapped() } label: { Text("review.submit", bundle: .module) }
                    .disabled(!state.canSubmit)
                    .accessibilityIdentifier("review-submit")
            }
            if let alert = state.alert {
                Section {
                    Text(LocalizedStringKey(alert), bundle: .module).foregroundStyle(.red)
                    Button { Task { await model.retry() } } label: { Text("review.retry", bundle: .module) }
                        .disabled(state.isBusy)
                }
            }
            Section {
                ForEach(state.items) { item in
                    Button { Task { await model.jumpToQuestion(index: item.index) } } label: {
                        HStack {
                            Text(String(format: String(localized: "review.question", bundle: .module), item.number))
                            Spacer()
                            if item.isUnanswered { Text("review.unanswered", bundle: .module) }
                            else { Text("review.answered", bundle: .module) }
                            if item.isFlagged {
                                Label { Text("review.flagged", bundle: .module) } icon: { Image(systemName: "flag.fill") }
                            }
                        }
                        .font(.body)
                    }
                    .disabled(!state.canSubmit)
                    .accessibilityIdentifier("review-question-\(item.number)")
                }
            } header: { Text("review.questions", bundle: .module) }
        }
        .navigationTitle(Text("review.title", bundle: .module))
        .sensoryFeedback(.warning, trigger: model.session.state.feedbackCount)
        // ダイアログ自体の自動dismissで、非同期の確認処理より先に確認状態を消さない。
        .alert(Text("review.confirmTitle", bundle: .module), isPresented: Binding(
            get: { model.state.confirmation != nil }, set: { _ in })) {
                Button { Task { await model.confirmSubmit() } } label: { Text("review.confirm", bundle: .module) }
                    .accessibilityIdentifier("review-confirm")
                Button(role: .cancel) { model.cancelSubmit() } label: { Text("exam.cancel", bundle: .module) }
        } message: {
            if let confirmation = state.confirmation {
                Text(counts(unanswered: confirmation.unansweredCount, flagged: confirmation.flaggedCount))
            }
        }
        .task { await model.load() }
        .onChange(of: scenePhase) { _, phase in
            guard phase != .inactive else { return }
            Task { await model.session.scenePhaseChanged(isActive: phase == .active) }
        }
        .onDisappear { Task { await model.session.viewDisappeared() } }
    }
    private func counts(unanswered: Int, flagged: Int) -> String {
        String(format: String(localized: "review.counts", bundle: .module), unanswered, flagged)
    }
}
