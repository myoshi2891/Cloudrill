import DomainModels
import DomainInterfaces

public struct ContentBootstrapResult: Sendable {
    public var available: [ExamID: any ExamContentProvider]
    public var failures: [ExamID: ContentError]

    /// P4 はこれを E-01 の表示に使う。個別の失敗は failures から参照する。
    public var fatalError: ContentError? {
        available.isEmpty ? .storage("no usable exam") : nil
    }
}

/// 起動時に試験ごとのパックを読み込む。1試験の不備で他の試験の利用を妨げない。
public struct ContentBootstrapper: Sendable {
    private let catalogService: ExamCatalogService
    private let loader: PackLoader
    private let integrityChecker: ContentIntegrityChecker

    public init(
        catalogService: ExamCatalogService,
        loader: PackLoader = PackLoader(),
        integrityChecker: ContentIntegrityChecker
    ) {
        self.catalogService = catalogService
        self.loader = loader
        self.integrityChecker = integrityChecker
    }

    public func bootstrap() async -> ContentBootstrapResult {
        var result = ContentBootstrapResult(available: [:], failures: [:])
        // entries() は状態を読むので、全試験をまとめて呼ばず、失敗を試験単位で扱う。
        for entry in catalogService.catalogEntries where entry.status != .comingSoon {
            do {
                if entry.status == .retired,
                   try await catalogService.activeLocation(for: entry.id) == nil { continue }
                result.available[entry.id] = try await catalogService.load(
                    for: entry.id, loader: loader, integrityChecker: integrityChecker
                )
            } catch {
                result.failures[entry.id] = error
            }
        }
        return result
    }
}
