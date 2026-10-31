import SwiftUI
import OSLog
import AppCore
import HomeFeature
import ExamFeature
import PracticeFeature
import FlashcardFeature
import LearnFeature
import AnalyticsFeature
import DomainModels
import DomainInterfaces

/// 起動失敗を空画面にせず表示する。依存の生成は View の task で一度だけ実行する。
public struct AppRootView: View {
    @State private var environment: AppEnvironment?
    @State private var failed = false
    private let packsRoot: URL?
    private let arguments: [String]

    public init(packsRoot: URL? = Bundle.main.url(forResource: "Packs", withExtension: nil),
                arguments: [String] = Array(ProcessInfo.processInfo.arguments.dropFirst())) {
        self.packsRoot = packsRoot; self.arguments = arguments
    }

    public var body: some View {
        Group {
            if let environment {
                ExamLandingView(context: environment.activeExam)
                    .environment(\.appDependencies, environment.dependencies)
            } else if failed {
                ContentUnavailableView {
                    Label { Text("error.contentLoadFailed", bundle: .module) } icon: { Image(systemName: "exclamationmark.triangle") }
                }
            } else { ProgressView().accessibilityLabel(Text("loading", bundle: .module)) }
        }
        .task {
            guard environment == nil, !failed else { return }
            do {
                guard let packsRoot else { throw CocoaError(.fileNoSuchFile) }
                #if DEBUG
                let support = try FileManager.default.url(for: .applicationSupportDirectory, in: .userDomainMask,
                                                           appropriateFor: nil, create: true)
                if arguments.contains("-ui-testing") {
                    let config = try UITestingConfiguration(arguments: arguments)
                    let working = config.storeDirectory ?? FileManager.default.temporaryDirectory.appending(path: "CloudrillUITest-\(UUID())")
                    environment = try await AppEnvironment.uiTesting(arguments: arguments, packsRoot: packsRoot, workingDirectory: working)
                } else {
                    environment = try await AppEnvironment.development(packsRoot: packsRoot,
                        storeDirectory: support.appending(path: "CloudrillDevelopment"))
                }
                #else
                guard let group = Bundle.main.object(forInfoDictionaryKey: "CloudrillAppGroup") as? String,
                      let directory = FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: group) else {
                    throw CocoaError(.fileNoSuchFile)
                }
                environment = try await AppEnvironment.live(packsRoot: packsRoot, storeDirectory: directory)
                #endif
            } catch {
                Logger(subsystem: "Cloudrill", category: "content").error("アプリの起動に失敗しました")
                failed = true
            }
        }
    }
}

private struct ExamLandingView: View {
    let context: ActiveExamContext
    @State private var showsPicker = false

    @Environment(\.appDependencies) private var dependencies

    var body: some View {
        Group {
            if context.state.fatal != nil {
                Text("error.contentLoadFailed", bundle: .module)
            } else if let content = context.content, let dependencies {
                MainTabView(context: context, content: content, dependencies: dependencies,
                            selectExam: { showsPicker = true })
                    .id(context.state.examID)
            } else {
                NavigationStack { PickerContent(context: context) }
            }
        }
        .sheet(isPresented: $showsPicker) {
            NavigationStack { PickerContent(context: context) { showsPicker = false } }
        }
    }
}

/// 後続のFeature画面は、タブとRouteごとの接続点を置き換える。
private struct MainTabView: View {
    let context: ActiveExamContext
    let content: any ExamContentProvider
    let dependencies: AppDependencies
    let selectExam: () -> Void
    @State private var home: HomeViewModel
    @State private var sessions: ExamSessionStore
    @State private var submittedContent: SubmittedExamContentCache
    @State private var decks: DeckListViewModel
    @State private var analytics: AnalyticsViewModel

    /// HomeViewModel は body の再評価(タブ切替・遷移)のたびに作り直さない。試験の切替は .id で作り直す。
    init(context: ActiveExamContext, content: any ExamContentProvider, dependencies: AppDependencies,
         selectExam: @escaping () -> Void) {
        self.context = context; self.content = content; self.dependencies = dependencies; self.selectExam = selectExam
        _sessions = State(initialValue: ExamSessionStore(examID: content.definition.id, dependencies: dependencies, router: context.router))
        _submittedContent = State(initialValue: SubmittedExamContentCache())
        _decks = State(initialValue: DeckListViewModel(content: content, cards: dependencies.cards,
            settings: dependencies.settings, time: dependencies.time, calendar: .autoupdatingCurrent, router: context.router))
        _home = State(initialValue: HomeViewModel(definition: content.definition,
            answers: dependencies.answers, cards: dependencies.cards,
            attempts: dependencies.attempts, time: dependencies.time, router: context.router))
        _analytics = State(initialValue: AnalyticsViewModel(definition: content.definition, answers: dependencies.answers))
    }

    var body: some View {
        @Bindable var router = context.router
        TabView(selection: $router.selectedTab) {
            ForEach(AppCore.Tab.allCases, id: \.self) { tab in
                NavigationStack(path: Binding(get: { router.path(for: tab) },
                                               set: { router.setPath($0, for: tab) })) {
                    Group {
                        if tab == .home {
                            HomeView(model: home, trademarkNotice: content.vendor.trademarkNotice,
                                     selectExam: selectExam)
                        } else if tab == .exam {
                            ExamTopView(content: content, router: router)
                        } else if tab == .cards {
                            DeckListView(model: decks)
                                // 学習から一覧(ルート)へ戻ったら今日の枚数を読み直す
                                .onChange(of: router.path(for: .cards).isEmpty) { _, isEmpty in
                                    guard isEmpty else { return }
                                    Task { await decks.refresh() }
                                }
                        } else if tab == .learn {
                            LearnTopView(content: content, router: router)
                        } else if tab == .analytics {
                            AnalyticsView(model: analytics)
                        } else {
                            pending(tab)
                        }
                    }
                    .navigationDestination(for: Route.self) { route in
                        switch route {
                        case .practiceSetup(let preset):
                            PracticeView(model: PracticeViewModel(content: content, preset: preset,
                                answers: dependencies.answers, cards: dependencies.cards, time: dependencies.time,
                                router: router, seedProvider: dependencies.seedProvider))
                        case .docsIndex(let domain):
                            DocsIndexView(model: DocsIndexViewModel(content: content, domain: domain, router: router))
                        case .doc(let subObjective):
                            DocView(model: DocViewModel(content: content, subObjective: subObjective))
                        case .caseList:
                            CaseListView(model: CaseListViewModel(content: content, router: router))
                        case .caseDetail(let id):
                            CaseDetailView(model: CaseDetailViewModel(content: content, id: id, router: router))
                        case .cardSession(let deck):
                            CardSessionView(model: CardSessionViewModel(content: content, deck: deck, cards: dependencies.cards,
                                settings: dependencies.settings, time: dependencies.time, calendar: .autoupdatingCurrent, router: router))
                        case .examStart(let set):
                            ExamStartView(content: content, examSet: set, dependencies: dependencies, router: router)
                        case .examSession(let id):
                            ExamSessionView(model: sessions.model(for: id))
                        case .examReview(let id):
                            ExamReviewView(session: sessions.model(for: id))
                        case .examResult(let id):
                            ExamResultView(model: ExamResultViewModel(examID: content.definition.id, attemptID: id,
                                resolver: dependencies.contentResolver, attempts: dependencies.attempts, router: router,
                                contentCache: submittedContent))
                        case .explanation(let attemptID, let questionID):
                            if let attemptID {
                                ExplanationView(model: ExplanationViewModel(examID: content.definition.id, attemptID: attemptID,
                                    questionID: questionID, resolver: dependencies.contentResolver, attempts: dependencies.attempts,
                                    cards: dependencies.cards, time: dependencies.time, router: router,
                                    contentCache: submittedContent))
                            } else { pending(.exam) }
                        default: pending(route.tab)
                        }
                    }
                }
                .tabItem { Label { Text(LocalizedStringKey("tab." + tab.rawValue), bundle: .module) }
                    icon: { Image(systemName: symbol(tab)) } }
                .tag(tab)
            }
        }
    }

    private func pending(_ tab: AppCore.Tab) -> some View {
        ContentUnavailableView {
            Label { Text(LocalizedStringKey("tab." + tab.rawValue), bundle: .module) }
                icon: { Image(systemName: symbol(tab)) }
        } description: { Text("featurePending", bundle: .module) }
    }

    private func symbol(_ tab: AppCore.Tab) -> String {
        switch tab {
        case .home: "house"
        case .exam: "checklist"
        case .cards: "rectangle.on.rectangle"
        case .learn: "book"
        case .analytics: "chart.bar"
        }
    }
}

private struct PickerContent: View {
    let context: ActiveExamContext
    var onSelected: () -> Void = {}
    @State private var requested: ExamID?

    var body: some View {
        let picker = ExamPickerViewModel(context: context)
        List {
            ForEach(picker.state.items) { item in
                Button { requested = item.id } label: {
                    VStack(alignment: .leading) {
                        Text(item.name.ja)
                        if item.status == .comingSoon { Text("comingSoon", bundle: .module).font(.caption) }
                    }
                }
                .disabled(!item.isSelectable || picker.state.isLoading)
                .accessibilityIdentifier("exam-\(item.id)")
            }
            if let alert = picker.state.alert { Text(LocalizedStringKey(alert.rawValue), bundle: .module).foregroundStyle(.red) }
            if let notice = picker.state.trademarkNotice { Text(notice.ja).font(.footnote) }
        }
        .navigationTitle(Text("chooseExam", bundle: .module))
        .task(id: requested) {
            guard let id = requested else { return }
            await picker.select(id)
            if context.state.examID == id { onSelected() }
            requested = nil
        }
    }
}
