import SwiftUI
import AppCore
import DesignSystem
import DomainModels
import DomainInterfaces

public struct ExamSessionView: View {
    @State private var model: ExamSessionViewModel
    @State private var showsCase = false
    @State private var timelineStart = Date()
    @Environment(\.scenePhase) private var scenePhase

    public init(model: ExamSessionViewModel) {
        _model = State(initialValue: model)
    }
    public var body: some View {
        let state = model.state
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                if let question = state.question {
                    HStack {
                        Text(String(format: String(localized: "session.progress", bundle: .module), state.currentIndex + 1, state.totalCount))
                            .accessibilityIdentifier("session-progress")
                        Spacer()
                        TimelineView(.periodic(from: timelineStart, by: 1)) { context in
                            TimerLabel(remainingSeconds: state.remainingSeconds)
                                .task(id: Int(context.date.timeIntervalSince1970)) { await model.tick() }
                        }
                    }
                    if let warning = state.warning {
                        Text(LocalizedStringKey(warning == .tenMinutes ? "session.tenMinutes" : "session.fiveMinutes"), bundle: .module)
                    }
                    if state.caseStudy != nil {
                        Button { showsCase = true } label: { Text("session.case", bundle: .module) }
                            .accessibilityIdentifier("session-case")
                    }
                    QuestionRendererRegistry.standard.render(question, selected: state.selected) { id in
                        Task { await model.select(choiceID: id) }
                    }
                    .disabled(state.isBusy || state.sessionState != .inProgress)
                    Button { Task { await model.toggleFlag() } } label: {
                        Label { Text(LocalizedStringKey(state.isFlagged ? "session.flagged" : "session.flag"), bundle: .module) }
                        icon: { Image(systemName: state.isFlagged ? "flag.fill" : "flag") }
                    }
                    .accessibilityIdentifier("session-flag")
                    .disabled(state.isBusy || state.sessionState != .inProgress)
                    HStack {
                        Button { Task { await model.move(to: state.currentIndex - 1) } } label: { Text("session.previous", bundle: .module) }
                            .disabled(state.currentIndex == 0)
                            .accessibilityIdentifier("session-previous")
                        Spacer()
                        Button { Task { await model.move(to: state.currentIndex + 1) } } label: { Text("session.next", bundle: .module) }
                            .disabled(state.currentIndex + 1 == state.totalCount)
                            .accessibilityIdentifier("session-next")
                    }
                    .disabled(state.isBusy || state.sessionState != .inProgress)
                    Button { Task { await model.openReview() } } label: {
                        Label { Text("review.open", bundle: .module) } icon: { Image(systemName: "checklist") }
                    }
                    .disabled(state.isBusy || state.sessionState != .inProgress)
                    .accessibilityIdentifier("session-review")
                } else if state.isBusy { ProgressView() }
                if let alert = state.alert {
                    if alert == "session.selectionLimit" {
                        Text(String(format: String(localized: "session.selectionLimit", bundle: .module), state.question?.requiredSelections ?? 0))
                    } else {
                        Text(LocalizedStringKey(alert), bundle: .module).foregroundStyle(.red)
                        Button { Task { await model.load() } } label: { Text("exam.retry", bundle: .module) }
                            .disabled(state.isBusy)
                    }
                }
            }
            .padding()
        }
        .navigationTitle(Text("session.title", bundle: .module))
        .sensoryFeedback(.warning, trigger: state.feedbackCount)
        .task {
            await model.showQuestions()
            await model.scenePhaseChanged(isActive: scenePhase == .active)
        }
        .onChange(of: scenePhase) { _, phase in
            // システムの一時的な inactive (通知等) では中断しない。
            guard phase != .inactive else { return }
            Task { await model.scenePhaseChanged(isActive: phase == .active) }
        }
        .onDisappear { Task { await model.viewDisappeared() } }
        .sheet(isPresented: $showsCase) {
            if let item = state.caseStudy { CaseSheetView(caseStudy: item) }
        }
    }
}
