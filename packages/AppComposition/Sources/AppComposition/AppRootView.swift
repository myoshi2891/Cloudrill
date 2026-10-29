import SwiftUI
import OSLog
import AppCore
import HomeFeature
import DomainModels

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

    var body: some View {
        NavigationStack {
            if context.state.fatal != nil {
                Text("error.contentLoadFailed", bundle: .module)
            } else if context.state.needsSelection {
                PickerContent(context: context)
            } else if let content = context.content {
                List {
                    Section { Text(content.definition.name.ja).font(.headline) }
                    Section {
                        ForEach(content.definition.domains, id: \.id) { domain in Text(domain.name.ja) }
                    } header: { Text("domains", bundle: .module) }
                    Section { Text(content.vendor.trademarkNotice.ja).font(.footnote) }
                }
                .id(context.state.examID)
                .toolbar {
                    ToolbarItem(placement: .principal) {
                        Button(content.definition.shortName) { showsPicker = true }
                            .accessibilityIdentifier("examPickerButton")
                    }
                }
                .sheet(isPresented: $showsPicker) {
                    NavigationStack { PickerContent(context: context) { showsPicker = false } }
                }
            }
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
