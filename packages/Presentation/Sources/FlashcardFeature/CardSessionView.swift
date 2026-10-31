import SwiftUI
import AppCore
import DomainModels
import FSRS

/// カード学習(SCR-031)と学習完了(SCR-032)
public struct CardSessionView: View {
    @State private var model: CardSessionViewModel
    public init(model: CardSessionViewModel) { _model = State(initialValue: model) }
    public var body: some View {
        Group {
            switch model.state.phase {
            case .idle:
                if model.state.alert != nil {
                    ContentUnavailableView {
                        error
                    } actions: {
                        Button { Task { await model.start() } } label: { Text("card.retry", bundle: .module) }
                    }
                } else { ProgressView() }
            case .studying: studying
            case .empty:
                ContentUnavailableView { Text("card.empty", bundle: .module) } actions: { backButton }
                    .accessibilityIdentifier("card-empty")
            case .finished: finished
            }
        }
        .navigationTitle(Text(model.state.phase == .finished ? "card.finished" : "card.title", bundle: .module))
        .disabled(model.state.isBusy && model.state.phase == .studying)
        .task { await model.start() }
    }
    private var studying: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                Text(String(format: String(localized: "card.progress", bundle: .module), model.state.index + 1, model.faces.count))
                    .font(.subheadline).foregroundStyle(.secondary)
                if let face = model.current {
                    bilingual(face.front).font(.title3).accessibilityIdentifier("card-front")
                    if model.state.showsBack {
                        Divider()
                        bilingual(face.back).font(.body).accessibilityIdentifier("card-back")
                        if let note = face.note { bilingual(note).font(.callout).foregroundStyle(.secondary) }
                    }
                }
                error
                if model.state.showsBack { ratingButtons } else {
                    Button { model.flip() } label: { Text("card.showAnswer", bundle: .module).frame(maxWidth: .infinity) }
                        .buttonStyle(.borderedProminent).accessibilityIdentifier("card-flip")
                }
            }.padding()
        }
    }
    private var ratingButtons: some View {
        HStack(spacing: 8) {
            ForEach(model.intervals, id: \.rating) { item in
                Button { Task { await model.rate(item.rating) } } label: {
                    VStack {
                        Text(LocalizedStringKey(Self.titleKey(item.rating)), bundle: .module).font(.subheadline.weight(.semibold))
                        Text(item.interval.label).font(.caption)
                    }.frame(maxWidth: .infinity)
                }
                .buttonStyle(.bordered)
                .accessibilityIdentifier("card-rate-\(Self.key(item.rating))")
            }
        }
    }
    /// FR-CARD-06: 日本語を主に、英語があれば併記する
    private func bilingual(_ text: LocalizedText) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(text.ja)
            if let en = text.en, en != text.ja { Text(en).foregroundStyle(.secondary).font(.callout) }
        }.frame(maxWidth: .infinity, alignment: .leading)
    }
    private var finished: some View {
        List {
            Text(String(format: String(localized: "card.finishedCount", bundle: .module), model.state.studied))
                .accessibilityIdentifier("card-finished-count")
            ForEach(Rating.allCases, id: \.self) { rating in
                LabeledContent {
                    Text(String(model.state.ratings[rating, default: 0]))
                } label: { Text(LocalizedStringKey(Self.titleKey(rating)), bundle: .module) }
            }
            backButton
        }
    }
    private var backButton: some View {
        Button { model.backToDecks() } label: { Text("card.backToDecks", bundle: .module) }
            .accessibilityIdentifier("card-back-to-decks")
    }
    @ViewBuilder private var error: some View {
        if let alert = model.state.alert { Text(LocalizedStringKey(alert), bundle: .module).foregroundStyle(.red) }
    }
    /// 補間を含むリテラルは書式キー(card.rating.%@)になるため、完成したキー文字列を渡す
    private static func titleKey(_ rating: Rating) -> String { "card.rating." + key(rating) }
    private static func key(_ rating: Rating) -> String {
        switch rating {
        case .again: "again"
        case .hard: "hard"
        case .good: "good"
        case .easy: "easy"
        }
    }
}
