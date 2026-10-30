import Foundation
import DomainModels
import DomainInterfaces
import StudyModels
import ExamEngine
import ContentKit
import Persistence
import AppCore
import ExamFeature

public enum AppEnvironmentError: Error, Equatable {
    case developmentContentNotAllowed, fixtureUnavailable, registryMismatch
}

@MainActor public final class AppEnvironment {
    public let dependencies: AppDependencies
    public let activeExam: ActiveExamContext
    public let packStore: PackStore
    public let isInMemory: Bool

    private static var evaluatedKinds: Set<QuestionKind> {
        Set(QuestionKind.allCases.filter { AnswerEvaluatorRegistry.standard.supports($0) })
    }

    public static var supportedKinds: Set<QuestionKind> {
        evaluatedKinds.intersection(QuestionRendererRegistry.standard.supportedKinds)
    }

    private init(dependencies: AppDependencies, activeExam: ActiveExamContext, packStore: PackStore, isInMemory: Bool) {
        self.dependencies = dependencies; self.activeExam = activeExam; self.packStore = packStore; self.isInMemory = isInMemory
    }

    /// 保存先はアプリが解決した App Group の URL を渡す。
    public static func live(packsRoot: URL, storeDirectory: URL) async throws -> AppEnvironment {
        guard !FileManager.default.fileExists(atPath: packsRoot.appending(path: "development.json").path) else {
            throw AppEnvironmentError.developmentContentNotAllowed
        }
        return try await make(bundled: BundledPacks(root: packsRoot), storeDirectory: storeDirectory,
                              contentDirectory: storeDirectory.appending(path: "Content"), time: SystemTimeSource())
    }

    #if DEBUG
    public static func uiTesting(arguments: [String], packsRoot: URL, workingDirectory: URL) async throws -> AppEnvironment {
        let configuration = try UITestingConfiguration(arguments: arguments)
        let bundled = try testingBundle(root: packsRoot, fixture: configuration.fixture)
        // インメモリでも PackStore は状態ファイルを使うため、専用の作業先を渡す。
        return try await make(bundled: bundled, storeDirectory: configuration.storeDirectory,
                              contentDirectory: workingDirectory.appending(path: "Content"),
                              time: UITestingTimeSource(configuration.date), seed: { 42 })
    }

    public static func development(packsRoot: URL, storeDirectory: URL) async throws -> AppEnvironment {
        try await make(bundled: BundledPacks(root: packsRoot), storeDirectory: storeDirectory,
                       contentDirectory: storeDirectory.appending(path: "Content"), time: SystemTimeSource())
    }

    private static func testingBundle(root: URL, fixture: String?) throws -> BundledPacks {
        let bundled = try BundledPacks(root: root)
        guard let fixture else { return bundled }
        var catalog = bundled.catalog
        catalog.exams = catalog.exams.filter { $0.id.rawValue == fixture && $0.status == .available }
        guard catalog.exams.count == 1 else { throw AppEnvironmentError.fixtureUnavailable }
        catalog.exams[0].latestPackVersion = "1.0.0"
        return BundledPacks(root: root, catalog: catalog)
    }
    #endif

    private static func make(bundled: BundledPacks, storeDirectory: URL?, contentDirectory: URL,
                             time: any TimeSource, seed: @escaping @Sendable () -> UInt64 = { UInt64.random(in: .min ... .max) }) async throws -> AppEnvironment {
        guard evaluatedKinds == QuestionRendererRegistry.standard.supportedKinds else { throw AppEnvironmentError.registryMismatch }
        let container = try ModelContainerFactory.make(inMemory: storeDirectory == nil, cloudKitContainer: nil, storeDirectory: storeDirectory)
        let store = PackStore(root: contentDirectory, bundledRoot: bundled.root)
        let dependencies = AppDependencies(contentResolver: ExamContentResolver(bundled: bundled, store: store, supportedKinds: supportedKinds),
            pins: store, attempts: SwiftDataExamAttemptRepository(modelContainer: container),
            answers: SwiftDataAnswerHistoryRepository(modelContainer: container), cards: SwiftDataCardStateRepository(modelContainer: container),
            bookmarks: SwiftDataBookmarkRepository(modelContainer: container), settings: SwiftDataSettingsRepository(modelContainer: container),
            dataManagement: DataManagement(modelContainer: container), time: time, seedProvider: seed)
        let catalogService = ExamCatalogService(bundled: bundled, store: store, cachedCatalog: nil)
        let loaded = await ContentBootstrapper(catalogService: catalogService,
            integrityChecker: ContentIntegrityChecker(supportedKinds: supportedKinds)).bootstrap()
        let entries = try await catalogService.entries().map(\.entry)
        let active = ActiveExamContext(available: loaded.available, catalog: entries, failures: Set(loaded.failures.keys),
            settings: dependencies.settings, attempts: dependencies.attempts, time: time, router: AppRouter())
        await active.restore()
        return AppEnvironment(dependencies: dependencies, activeExam: active, packStore: store, isInMemory: storeDirectory == nil)
    }
}
