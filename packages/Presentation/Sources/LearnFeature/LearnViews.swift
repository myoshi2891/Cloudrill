import SwiftUI
import AppCore
import DomainModels
import DomainInterfaces
import DesignSystem

/// 学ぶトップ(SCR-040)。登録表のうち、この試験で有効な学習機能だけを出す
public struct LearnTopView: View {
    private let modules: [LearnModule]
    private let router: AppRouter
    public init(content: any ExamContentProvider, router: AppRouter, registry: LearnModuleRegistry = .standard) {
        modules = registry.modules(for: content.definition.features); self.router = router
    }
    public var body: some View {
        Group {
            if modules.isEmpty {
                ContentUnavailableView { Text("learn.empty", bundle: .module) }
            } else {
                List(modules) { module in
                    Button { router.open(module.route) } label: {
                        Label { Text(LocalizedStringKey(module.titleKey), bundle: .module) } icon: { Image(systemName: module.symbol) }
                    }
                    .accessibilityIdentifier("learn-module-\(module.id)")
                }
            }
        }
        .navigationTitle(Text("learn.title", bundle: .module))
    }
}

/// ドメイン目次(SCR-041)
public struct DocsIndexView: View {
    @State private var model: DocsIndexViewModel
    public init(model: DocsIndexViewModel) { _model = State(initialValue: model) }
    public var body: some View {
        Group {
            if !model.isAvailable {
                ContentUnavailableView { Text("docs.unavailable", bundle: .module) }
            } else {
                List(model.sections) { section in
                    Section {
                        ForEach(section.rows) { row in
                            Button { model.open(row) } label: { label(row) }
                                .disabled(!row.isAvailable)
                                .accessibilityIdentifier("doc-row-\(row.id)")
                        }
                    } header: { DomainBadge(index: section.domainIndex, title: section.name.ja) }
                }
            }
        }
        .navigationTitle(Text("docs.title", bundle: .module))
    }
    private func label(_ row: DocsIndexRow) -> some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text("\(row.id) \(row.name.ja)")
                if let title = row.title { Text(title).font(.caption).foregroundStyle(.secondary) }
            }
            Spacer()
            if !row.isAvailable { Text("docs.preparing", bundle: .module).font(.caption).foregroundStyle(.secondary) }
        }
    }
}

/// ドキュメント閲覧(SCR-042)
public struct DocView: View {
    @State private var model: DocViewModel
    public init(model: DocViewModel) { _model = State(initialValue: model) }
    public var body: some View {
        Group {
            switch model.phase {
            case .idle: ProgressView()
            case .notFound:
                ContentUnavailableView { Text("doc.notFound", bundle: .module) }
                    .accessibilityIdentifier("doc-not-found")
            case .failed:
                ContentUnavailableView { Text("doc.loadFailed", bundle: .module) } actions: {
                    Button { Task { await model.load() } } label: { Text("doc.retry", bundle: .module) }
                }
            case .loaded(let document):
                ScrollView {
                    VStack(alignment: .leading, spacing: 16) {
                        MarkdownView(document: document).accessibilityIdentifier("doc-body")
                        if !model.references.isEmpty {
                            Divider()
                            Text("doc.references", bundle: .module).font(.headline).accessibilityAddTraits(.isHeader)
                            ForEach(Array(model.references.enumerated()), id: \.offset) { index, reference in
                                ReferenceLink(reference).accessibilityIdentifier("doc-reference-\(index)")
                            }
                        }
                    }.padding()
                }
            }
        }
        .navigationTitle(model.title)
        .navigationBarTitleDisplayModeInline()
        .task { await model.load() }
    }
}

/// ケーススタディの一覧(SCR-043)
public struct CaseListView: View {
    @State private var model: CaseListViewModel
    public init(model: CaseListViewModel) { _model = State(initialValue: model) }
    public var body: some View {
        Group {
            if !model.isAvailable {
                ContentUnavailableView { Text("cases.unavailable", bundle: .module) }
            } else {
                switch model.phase {
                case .idle: ProgressView()
                case .failed:
                    ContentUnavailableView { Text("cases.loadFailed", bundle: .module) } actions: {
                        Button { Task { await model.load() } } label: { Text("doc.retry", bundle: .module) }
                    }
                case .loaded(let cases):
                    List(cases) { item in
                        Button { model.open(item.id) } label: {
                            VStack(alignment: .leading, spacing: 2) {
                                Text(item.name.ja)
                                Text(item.summary.ja).font(.caption).foregroundStyle(.secondary).lineLimit(2)
                            }
                        }
                        .accessibilityIdentifier("case-row-\(item.id.rawValue)")
                    }
                }
            }
        }
        .navigationTitle(Text("cases.title", bundle: .module))
        .task { await model.load() }
    }
}

/// ケーススタディの詳細(SCR-044)
public struct CaseDetailView: View {
    @State private var model: CaseDetailViewModel
    public init(model: CaseDetailViewModel) { _model = State(initialValue: model) }
    public var body: some View {
        Group {
            switch model.phase {
            case .idle: ProgressView()
            case .notFound:
                ContentUnavailableView { Text("case.notFound", bundle: .module) }
                    .accessibilityIdentifier("case-not-found")
            case .failed:
                ContentUnavailableView { Text("case.loadFailed", bundle: .module) } actions: {
                    Button { Task { await model.load() } } label: { Text("doc.retry", bundle: .module) }
                }
            case .loaded(let caseStudy):
                List {
                    CaseStudySections(caseStudy)
                    Section {
                        Button { model.practice() } label: { Text("case.practice", bundle: .module) }
                            .accessibilityIdentifier("case-practice")
                    }
                }
                .navigationTitle(caseStudy.name.ja)
            }
        }
        .navigationBarTitleDisplayModeInline()
        .task { await model.load() }
    }
}

private extension View {
    /// macOS でもテストのためにビルドできるよう、iOS だけで指定する
    @ViewBuilder func navigationBarTitleDisplayModeInline() -> some View {
        #if os(iOS)
        navigationBarTitleDisplayMode(.inline)
        #else
        self
        #endif
    }
}
