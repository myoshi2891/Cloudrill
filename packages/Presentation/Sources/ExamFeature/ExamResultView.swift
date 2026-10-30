import SwiftUI
import DesignSystem

public struct ExamResultView: View {
    @State private var model: ExamResultViewModel
    public init(model: ExamResultViewModel) { _model = State(initialValue: model) }

    public var body: some View {
        List {
            if let summary = model.summary {
                Section {
                    Text(LocalizedStringKey(summary.reason == .timeExpired ? "session.expired" : "session.submitted"), bundle: .module)
                        .accessibilityIdentifier("session-submitted")
                    Text(model.scoreText).font(.title.bold()).accessibilityIdentifier("result-score")
                    Text(String(format: String(localized: "result.elapsed", bundle: .module), model.elapsedMinutes))
                        .accessibilityIdentifier("result-elapsed")
                } header: { Text("result.total", bundle: .module) }
                Section {
                    ForEach(model.domains) { row in breakdown(row) }
                } header: { Text("result.domains", bundle: .module) }
                if !model.cases.isEmpty {
                    Section {
                        ForEach(model.cases) { row in breakdown(row) }
                    } header: { Text("result.cases", bundle: .module) }
                }
                Section {
                    ForEach(model.questions) { question in
                        Button { model.openExplanation(questionID: question.id) } label: {
                            VStack(alignment: .leading, spacing: 8) {
                                Text(String(format: String(localized: "review.question", bundle: .module), question.number))
                                    .font(.headline)
                                if question.isUnanswered { Text("review.unanswered", bundle: .module) }
                                else { ResultBadge(isCorrect: question.isCorrect) }
                                Text(question.stem).lineLimit(3).foregroundStyle(.primary)
                            }
                            .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
                            .contentShape(Rectangle())
                        }
                        .accessibilityIdentifier("result-question-\(question.number)")
                    }
                } header: { Text("result.explanations", bundle: .module) }
            } else if model.isLoading { ProgressView() }
            if let error = model.error {
                Text(LocalizedStringKey(error), bundle: .module)
                Button { Task { await model.load() } } label: { Text("exam.retry", bundle: .module) }
            }
        }
        .navigationTitle(Text("session.result", bundle: .module))
        .task { await model.load() }
    }
    private func breakdown(_ row: ResultBreakdown) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(row.name)
            Text(ExamResultViewModel.scoreText(row.tally)).font(.headline)
        }
        .accessibilityElement(children: .combine)
    }
}
