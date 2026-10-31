import AppCore
import DomainModels

/// 学ぶタブ(SCR-040)の入口1つ
public struct LearnModule: Hashable, Sendable, Identifiable {
    public var id: String
    /// LearnFeature の Localizable.strings のキー
    public var titleKey: String
    public var symbol: String
    public var route: Route

    public init(id: String, titleKey: String, symbol: String, route: Route) {
        self.id = id; self.titleKey = titleKey; self.symbol = symbol; self.route = route
    }
}

/// 学習機能の登録表(DDD 4.9)。試験定義の `features` で有効なものだけを、登録の順に出す。
/// 新しい学習機能は Composition root で登録を足す(ツリーとドリルは P6)。
public struct LearnModuleRegistry: Sendable {
    public struct Entry: Sendable {
        public var module: LearnModule
        public var isEnabled: @Sendable (ExamFeatures) -> Bool
        public init(module: LearnModule, isEnabled: @escaping @Sendable (ExamFeatures) -> Bool) {
            self.module = module; self.isEnabled = isEnabled
        }
    }
    private let entries: [Entry]

    public init(entries: [Entry]) { self.entries = entries }

    public func modules(for features: ExamFeatures) -> [LearnModule] {
        entries.filter { $0.isEnabled(features) }.map(\.module)
    }

    public static let standard = LearnModuleRegistry(entries: [
        Entry(module: LearnModule(id: "docs", titleKey: "learn.module.docs", symbol: "doc.text", route: .docsIndex(domain: nil)),
              isEnabled: { $0.docs }),
        // ケースの本文は S13 で接続する
        Entry(module: LearnModule(id: "cases", titleKey: "learn.module.cases", symbol: "building.2", route: .caseList),
              isEnabled: { $0.caseStudies }),
    ])
}
