import SwiftUI
import AppCore
import DomainModels
import DesignSystem

/// デッキ一覧(SCR-030)。学習から戻るたびに今日の枚数を読み直す
public struct DeckListView: View {
    @State private var model: DeckListViewModel
    public init(model: DeckListViewModel) { _model = State(initialValue: model) }
    public var body: some View {
        Group {
            if !model.isAvailable {
                ContentUnavailableView { Text("card.unavailable", bundle: .module) }
                    .accessibilityIdentifier("card-unavailable")
            } else if let alert = model.state.alert {
                ContentUnavailableView {
                    Text(LocalizedStringKey(alert), bundle: .module)
                } actions: {
                    Button { Task { await model.refresh() } } label: { Text("card.retry", bundle: .module) }
                }
            } else if model.state.isLoaded && model.state.decks.isEmpty {
                ContentUnavailableView { Text("card.noDecks", bundle: .module) }
            } else {
                list
            }
        }
        .navigationTitle(Text("card.decks", bundle: .module))
        .task { await model.refresh() }
    }
    private var list: some View {
        List {
            section("card.section.all", decks: model.state.decks.filter { $0.kind == .all })
            section("card.section.domains", decks: model.state.decks.filter {
                switch $0.kind { case .domain, .subObjective: true; default: false }
            })
            section("card.section.mistakes", decks: model.state.decks.filter { $0.kind == .mistakes })
        }
        .overlay { if model.state.isLoading && !model.state.isLoaded { ProgressView() } }
    }
    @ViewBuilder private func section(_ title: LocalizedStringKey, decks: [Deck]) -> some View {
        if !decks.isEmpty {
            Section {
                ForEach(decks) { deck in
                    Button { model.open(deck) } label: { row(deck) }
                        .accessibilityIdentifier("deck-\(deck.id.rawValue)")
                }
            } header: { Text(title, bundle: .module) }
        }
    }
    private func row(_ deck: Deck) -> some View {
        HStack {
            if case .domain = deck.kind, let index = deck.domainIndex, let title = deck.title {
                DomainBadge(index: index, title: title.ja)
            } else {
                Text(deckTitle(deck)).padding(.leading, isSubObjective(deck) ? 16 : 0)
            }
            Spacer()
            VStack(alignment: .trailing) {
                Text(String(format: String(localized: "card.dueToday", bundle: .module), deck.dueToday)).font(.subheadline.weight(.semibold))
                Text(String(format: String(localized: "card.total", bundle: .module), deck.total)).font(.caption).foregroundStyle(.secondary)
            }
        }
    }
    private func deckTitle(_ deck: Deck) -> String {
        switch deck.kind {
        case .all: String(localized: "card.deck.all", bundle: .module)
        case .mistakes: String(localized: "card.deck.mistakes", bundle: .module)
        case .domain, .subObjective: deck.title?.ja ?? ""
        }
    }
    private func isSubObjective(_ deck: Deck) -> Bool {
        if case .subObjective = deck.kind { true } else { false }
    }
}
