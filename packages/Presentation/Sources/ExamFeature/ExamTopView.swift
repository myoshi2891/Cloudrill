import SwiftUI
import AppCore
import DomainInterfaces

public struct ExamTopView: View {
    private let model: ExamTopViewModel
    private let router: AppRouter
    public init(content: any ExamContentProvider, router: AppRouter) {
        model = ExamTopViewModel(content: content); self.router = router
    }
    public var body: some View {
        List {
            Button { router.open(.practiceSetup(nil)) } label: { Text("exam.practice", bundle: .module) }
                .accessibilityIdentifier("exam-practice")
            Section {
                ForEach(model.sets) { set in
                    Button { router.open(.examStart(examSet: set.id)) } label: {
                        Text(String(format: String(localized: "exam.set", bundle: .module), set.id))
                    }
                    .accessibilityIdentifier("exam-set-\(set.id)")
                }
                if model.sets.isEmpty { Text("exam.noSets", bundle: .module) }
            } header: { Text("exam.mockExams", bundle: .module) }
        }
        .navigationTitle(Text("exam.title", bundle: .module))
    }
}

public struct ExamStartView: View {
    @State private var model: ExamStartViewModel
    @State private var confirmsAbandon = false
    public init(content: any ExamContentProvider, examSet: Int, dependencies: AppDependencies, router: AppRouter) {
        _model = State(initialValue: ExamStartViewModel(content: content, examSet: examSet,
            attempts: dependencies.attempts, pins: dependencies.pins, settings: dependencies.settings,
            time: dependencies.time, seedProvider: dependencies.seedProvider, router: router))
    }
    public var body: some View {
        List {
            Section {
                Text(String(format: String(localized: "exam.format", bundle: .module), model.questionCount, model.durationMinutes))
                    .accessibilityIdentifier("exam-format")
                Text("exam.timerNotice", bundle: .module)
            }
            if !model.cases.isEmpty {
                Section {
                    ForEach(model.cases) { item in Text(item.name.ja) }
                } header: { Text("exam.cases", bundle: .module) }
            }
            if let error = model.error {
                Section {
                    Text(LocalizedStringKey(error), bundle: .module).foregroundStyle(.red)
                    Button { Task { await model.load() } } label: { Text("exam.retry", bundle: .module) }
                }
            }
            if model.inProgress != nil {
                Section {
                    Text("exam.inProgress", bundle: .module)
                    Button { Task { await model.resume() } } label: { Text("exam.resume", bundle: .module) }
                    Button(role: .destructive) { confirmsAbandon = true } label: { Text("exam.abandon", bundle: .module) }
                }
            } else {
                Button { Task { await model.start() } } label: { Text("exam.start", bundle: .module) }
                    .disabled(!model.isLoaded)
                    .accessibilityIdentifier("exam-start")
            }
        }
        .disabled(model.isBusy)
        .overlay { if model.isBusy { ProgressView() } }
        .navigationTitle(Text("exam.confirm", bundle: .module))
        .task { await model.load() }
        .confirmationDialog(Text("exam.abandonConfirm", bundle: .module), isPresented: $confirmsAbandon) {
            Button(role: .destructive) { Task { await model.abandon() } } label: { Text("exam.abandon", bundle: .module) }
            Button(role: .cancel) {} label: { Text("exam.cancel", bundle: .module) }
        }
    }
}
