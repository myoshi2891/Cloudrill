import SwiftUI
import AppCore
import DomainModels
import QuestionSelector
import ExamFeature

/// State is retained across tab changes; changing the active exam recreates this flow.
public struct PracticeView: View {
    @State private var model: PracticeViewModel
    public init(model: PracticeViewModel) { _model = State(initialValue: model) }
    public var body: some View {
        Group {
            switch model.state.phase {
            case .setup: setup
            case .answering:
                ScrollView {
                    VStack(alignment: .leading, spacing: 20) {
                        progress
                        if let question = model.current {
                            QuestionRendererRegistry.standard.render(question, selected: model.state.selectedIDs) { model.select($0) }
                        }
                        flagButton
                        error
                        Button { Task { await model.submit() } } label: { Text("practice.submit", bundle: .module) }
                            .buttonStyle(.borderedProminent).disabled(!model.canSubmit)
                            .accessibilityIdentifier("practice-submit")
                    }.padding()
                }
            case .feedback:
                VStack(spacing: 0) {
                    progress.padding()
                    if let explanation = model.explanation {
                        ExplanationView(model: explanation).id(model.current?.id)
                    }
                    error
                    Button { model.next() } label: {
                        Text(LocalizedStringKey(model.state.index + 1 == model.questions.count ? "practice.finish" : "practice.next"), bundle: .module)
                    }.buttonStyle(.borderedProminent).padding().accessibilityIdentifier("practice-next")
                }
            case .result: result
            }
        }
        .navigationTitle(Text(model.state.phase == .result ? "practice.result" : "practice.title", bundle: .module))
        .disabled(model.state.isBusy)
        .overlay { if model.state.isBusy { ProgressView() } }
    }
    private var progress: some View {
        Text(String(format: String(localized: "practice.progress", bundle: .module), model.state.index + 1, model.questions.count))
    }
    @ViewBuilder private var error: some View {
        if let alert = model.state.alert { Text(LocalizedStringKey(alert), bundle: .module).foregroundStyle(.red) }
    }
    private var flagButton: some View {
        Button { Task { await model.toggleFlag() } } label: {
            Label { Text("practice.flag", bundle: .module) } icon: {
                Image(systemName: model.state.flagged.contains(model.current?.id ?? "") ? "flag.fill" : "flag")
            }
        }.accessibilityIdentifier("practice-flag")
    }
    private var setup: some View {
        Form {
            Section {
                ForEach(model.domains) { domain in
                    Toggle(domain.name.ja, isOn: membership(domain.id, in: \.domains))
                    ForEach(domain.subObjectives) { sub in
                        Toggle("\(sub.id) \(sub.name.ja)", isOn: membership(sub.id, in: \.subObjectives))
                    }
                }
            } header: { Text("practice.domains", bundle: .module) }
            if !model.cases.isEmpty {
                Section {
                    ForEach(model.cases, id: \.self) { id in
                        Toggle(id.rawValue, isOn: membership(id, in: \.caseStudies))
                    }
                } header: { Text("practice.cases", bundle: .module) }
            }
            Section {
                Picker(selection: Binding(get: { model.criteria.difficulty?.lowerBound ?? 0 },
                    set: { model.criteria.difficulty = $0 == 0 ? nil : $0...$0 })) {
                    Text("practice.all", bundle: .module).tag(0)
                    ForEach(1...5, id: \.self) { Text(String($0)).tag($0) }
                } label: { Text("practice.difficulty", bundle: .module) }
                Picker(selection: Binding(get: { model.criteria.scope }, set: { model.criteria.scope = $0 })) {
                    Text("practice.all", bundle: .module).tag(PracticeScope.all)
                    Text("practice.wrong", bundle: .module).tag(PracticeScope.wrongOnly)
                    Text("practice.unanswered", bundle: .module).tag(PracticeScope.unanswered)
                    Text("practice.flagged", bundle: .module).tag(PracticeScope.flagged)
                } label: { Text("practice.scope", bundle: .module) }
                Picker(selection: Binding(get: { model.criteria.count }, set: { model.criteria.count = $0 })) {
                    ForEach(PracticeViewModel.countOptions, id: \.self) { count in
                        switch count {
                        case .fixed(let n): Text(String(n)).tag(count)
                        case .all: Text("practice.all", bundle: .module).tag(count)
                        }
                    }
                } label: { Text("practice.count", bundle: .module) }
            }
            error
            Button { Task { await model.start() } } label: { Text("practice.start", bundle: .module) }
                .accessibilityIdentifier("practice-start")
        }
    }
    private func membership<T: Hashable>(_ value: T, in key: WritableKeyPath<PracticeCriteria, Set<T>>) -> Binding<Bool> {
        Binding(get: { model.criteria[keyPath: key].contains(value) }, set: { selected in
            if selected { model.criteria[keyPath: key].insert(value) }
            else { model.criteria[keyPath: key].remove(value) }
        })
    }
    private var result: some View {
        List {
            Text(String(format: String(localized: "practice.score", bundle: .module), model.correctCount, model.state.answers.count))
                .accessibilityIdentifier("practice-score")
            ForEach(model.domains) { domain in
                LabeledContent(domain.name.ja) {
                    if let tally = model.summary.byDomain[domain.id], tally.total > 0 {
                        Text(String(format: String(localized: "practice.score", bundle: .module), tally.correct, tally.total))
                    } else { Text("practice.notAsked", bundle: .module) }
                }
            }
        }
    }
}
