import SwiftUI
import OSLog
import AppCore
import HomeFeature
import ExamFeature
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

    /// HomeViewModel は body の再評価(タブ切替・遷移)のたびに作り直さない。試験の切替は .id で作り直す。
    init(context: ActiveExamContext, content: any ExamContentProvider, dependencies: AppDependencies,
         selectExam: @escaping () -> Void) {
        self.context = context; self.content = content; self.dependencies = dependencies; self.selectExam = selectExam
        _home = State(initialValue: HomeViewModel(definition: content.definition,
            answers: dependencies.answers, cards: dependencies.cards,
            attempts: dependencies.attempts, time: dependencies.time, router: context.router))
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
                        } else {
                            pending(tab)
                        }
                    }
                    .navigationDestination(for: Route.self) { route in
                        switch route {
                        case .examStart(let set):
                            ExamStartView(content: content, examSet: set, dependencies: dependencies, router: router)
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
