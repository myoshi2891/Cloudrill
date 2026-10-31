import SwiftUI
import Charts
import DesignSystem
import DomainModels

/// 分析トップ(SCR-050)
public struct AnalyticsView: View {
    @State private var model: AnalyticsViewModel
    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.colorScheme) private var scheme
    public init(model: AnalyticsViewModel) { _model = State(initialValue: model) }

    public var body: some View {
        List {
            if model.state.loadFailed {
                Section {
                    Text("analytics.loadFailed", bundle: .module)
                    Button { Task { await model.refresh() } } label: { Text("analytics.retry", bundle: .module) }
                }
            }
            if !model.state.isLoaded && model.state.isLoading { ProgressView() }
            if model.state.isLoaded {
                if model.state.isEmpty {
                    Text("analytics.empty", bundle: .module).accessibilityIdentifier("analytics-empty")
                } else {
                    Section { chart } header: { Text("analytics.byDomain", bundle: .module) }
                }
                ForEach(model.state.sections) { section in
                    Section {
                        row(section.domain, title: String(localized: "analytics.overall", bundle: .module)).accessibilityIdentifier("analytics-domain-\(section.id)")
                        ForEach(section.subObjectives) { sub in
                            row(sub, title: "\(sub.id) \(sub.name.ja)").padding(.leading).accessibilityIdentifier("analytics-sub-\(sub.id)")
                        }
                    } header: { DomainBadge(index: section.domainIndex, title: section.domain.name.ja) }
                }
            }
        }
        .navigationTitle(Text("analytics.title", bundle: .module))
        .task { await model.refresh() }
        .refreshable { await model.refresh() }
        .onChange(of: scenePhase) { _, phase in
            if phase == .active { Task { await model.refresh() } }
        }
    }

    /// 解答のあるドメインだけを 0〜100% の横棒で出す
    private var chart: some View {
        let answered = model.state.sections.filter { $0.domain.tally.ratio != nil }
        return Chart(answered) { section in
            BarMark(x: .value("%", (section.domain.tally.ratio ?? 0) * 100),
                    y: .value("domain", section.domain.name.ja))
                .foregroundStyle(DomainPalette.color(forDomainAt: section.domainIndex, scheme: scheme))
                .annotation(position: .trailing) { Text(section.domain.accuracyText).font(.caption) }
        }
        .chartXScale(domain: 0...100)
        .frame(height: CGFloat(answered.count) * 44 + 24)
        .accessibilityIdentifier("analytics-chart")
    }

    private func row(_ row: AnalyticsRow, title: String) -> some View {
        HStack {
            Text(title)
            Spacer()
            VStack(alignment: .trailing, spacing: 2) {
                Text(row.accuracyText).font(.body.monospacedDigit())
                if row.tally.total > 0 {
                    Text(String(format: String(localized: "analytics.count", bundle: .module),
                                row.tally.correct, row.tally.total))
                        .font(.caption).foregroundStyle(.secondary)
                }
            }
        }
        .accessibilityElement(children: .combine)
    }
}
