import SwiftUI
import AppCore
import DesignSystem
import DomainModels

public struct HomeView: View {
    @State private var model: HomeViewModel
    @Environment(\.scenePhase) private var scenePhase
    private let trademarkNotice: LocalizedText
    private let selectExam: () -> Void

    /// trademarkNotice は試験のホームに常に表示する(LG-04)。
    public init(model: HomeViewModel, trademarkNotice: LocalizedText, selectExam: @escaping () -> Void) {
        _model = State(initialValue: model); self.trademarkNotice = trademarkNotice; self.selectExam = selectExam
    }

    public var body: some View {
        List {
            if model.state.alert != nil {
                Section {
                    Text("loadError", bundle: .module)
                    Button { Task { await model.refresh() } } label: { Text("retry", bundle: .module) }
                }
            }
            if !model.state.isLoaded && model.state.isLoading {
                ProgressView().accessibilityLabel(Text("loading", bundle: .module))
            }
            if model.state.isLoaded {
                if model.state.resumeAttemptID != nil {
                    Button(action: model.resumeExam) {
                        Label { Text("resume", bundle: .module) } icon: { Image(systemName: "play.circle") }
                    }.accessibilityIdentifier("homeResume")
                }
                Section {
                    Button(action: model.startLearning) { Text("start", bundle: .module) }
                        .accessibilityIdentifier("homeStartLearning")
                } header: { Text("today", bundle: .module) }
                if model.state.isHistoryLoaded { Section {
                    if let id = model.state.weakDomain,
                       let index = model.definition.domains.firstIndex(where: { $0.id == id }) {
                        DomainBadge(index: index, title: model.definition.domains[index].name.ja)
                        Button(action: model.practiceWeakDomain) { Text("practice", bundle: .module) }
                    } else {
                        Text("empty", bundle: .module).accessibilityIdentifier("homeNoData")
                    }
                } header: { Text("weakness", bundle: .module) } }
                if model.definition.features.flashcards && model.state.isCardsLoaded {
                    Section {
                        Text(String(format: String(localized: "dueCount", bundle: .module), model.state.dueCards))
                            .accessibilityIdentifier("homeDueCards")
                        Button(action: model.reviewCards) { Text("review", bundle: .module) }
                    } header: { Text("cards", bundle: .module) }
                }
            }
            Section {
                Text(trademarkNotice.ja).font(.footnote)
                    .accessibilityIdentifier("homeTrademarkNotice")
            }
        }
        .navigationTitle(model.title)
        #if os(iOS)
        .navigationBarTitleDisplayMode(.inline)
        #endif
        .toolbar {
            ToolbarItem(placement: .principal) {
                Button(model.title, action: selectExam).accessibilityIdentifier("examPickerButton")
            }
        }
        .task { await model.refresh() }
        .refreshable { await model.refresh() }
        .onChange(of: scenePhase) { _, phase in
            if phase == .active { Task { await model.refresh() } }
        }
    }
}
