import SwiftUI
import DesignSystem
import DomainModels
import AppCore
import SettingsFeature

public struct ExplanationView: View {
    @State private var model: ExplanationViewModel
    @Environment(\.appDependencies) private var dependencies
    public init(model: ExplanationViewModel) { _model = State(initialValue: model) }

    public var body: some View {
        List {
            if let question = model.question {
                Section {
                    if model.isUnanswered { Text("review.unanswered", bundle: .module) }
                    else { ResultBadge(isCorrect: model.isCorrect) }
                    Text(question.stem.text(preferEnglish: model.preferEnglish))
                        .accessibilityIdentifier("explanation-stem")
                }
                Section {
                    ForEach(model.choices) { choice in choiceRow(choice) }
                } header: { Text("explanation.choices", bundle: .module) }
                if !question.references.isEmpty {
                    Section {
                        ForEach(Array(question.references.enumerated()), id: \.offset) { _, reference in
                            ReferenceLink(reference)
                        }
                    } header: { Text("explanation.references", bundle: .module) }
                }
                Section {
                    if let subObjective = model.relatedDoc {
                        Button { model.openRelatedDoc() } label: {
                            Label(String(format: String(localized: "explanation.relatedDoc", bundle: .module), subObjective), systemImage: "book")
                        }
                        .accessibilityIdentifier("explanation-related-doc")
                    }
                    if model.canAddToCards {
                        Button { Task { await model.addToCards() } } label: {
                            Label { Text(LocalizedStringKey(model.isAddedToCards ? "explanation.cardAdded" : "explanation.addCard"), bundle: .module) }
                            icon: { Image(systemName: model.isAddedToCards ? "checkmark" : "rectangle.stack.badge.plus") }
                        }
                        .disabled(model.isAdding || model.isLoading || model.isAddedToCards)
                        .accessibilityIdentifier("explanation-add-card")
                    }
                    if let error = model.actionError {
                        Text(LocalizedStringKey(error), bundle: .module).foregroundStyle(.red)
                        Button { Task { await model.load() } } label: { Text("exam.retry", bundle: .module) }
                    }
                    Button { model.openReport() } label: {
                        Label { Text("explanation.report", bundle: .module) } icon: { Image(systemName: "exclamationmark.bubble") }
                    }
                    .accessibilityIdentifier("explanation-report")
                }
            } else if model.isLoading { ProgressView() }
            if let error = model.error {
                Text(LocalizedStringKey(error), bundle: .module)
                Button { Task { await model.load() } } label: { Text("exam.retry", bundle: .module) }
            }
        }
        .navigationTitle(Text("explanation.title", bundle: .module))
        .toolbar {
            if model.question != nil {
                Button { model.preferEnglish.toggle() } label: {
                    Text(LocalizedStringKey(model.preferEnglish ? "explanation.japanese" : "explanation.english"), bundle: .module)
                }
                .accessibilityIdentifier("explanation-language")
            }
        }
        .task { await model.load() }
        .sheet(item: Binding(get: { model.report }, set: { if $0 == nil { model.closeReport() } })) { context in
            if let dependencies { ReportSheetView(context: context, dependencies: dependencies) }
            else { QuestionReportEntryView(context: context) }
        }
    }
    private func choiceRow(_ choice: Choice) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            ResultBadge(isCorrect: choice.isCorrect)
            if model.selectedIDs.contains(choice.id) {
                Text("explanation.yourAnswer", bundle: .module).font(.headline)
            }
            Text("\(choice.id.uppercased()). \(choice.text.text(preferEnglish: model.preferEnglish))")
            Text(LocalizedStringKey(choice.isCorrect ? "explanation.whyCorrect" : "explanation.whyIncorrect"), bundle: .module)
                .font(.headline)
            Text(choice.rationale.text(preferEnglish: model.preferEnglish))
                .accessibilityIdentifier("explanation-rationale-\(choice.id)")
            if !choice.isCorrect {
                ForEach(choice.mistakeTags, id: \.self) { MistakeTagChip($0) }
            }
        }
        .padding(.vertical, 8)
    }
}

/// 依存が未注入(Preview)のときだけ使う読み取り専用の表示。未送信のものを送信済みとは表示しない。
private struct QuestionReportEntryView: View {
    let context: QuestionReportContext
    @Environment(\.dismiss) private var dismiss
    var body: some View {
        NavigationStack {
            List {
                Text("explanation.reportPending", bundle: .module)
                LabeledContent(String(localized: "explanation.reportQuestion", bundle: .module), value: context.questionID)
                LabeledContent(String(localized: "explanation.reportRevision", bundle: .module), value: String(context.questionRevision))
                LabeledContent(String(localized: "explanation.reportPack", bundle: .module), value: context.packVersion)
            }
            .navigationTitle(Text("explanation.report", bundle: .module))
            .toolbar {
                Button { dismiss() } label: { Text("session.close", bundle: .module) }
            }
        }
    }
}
