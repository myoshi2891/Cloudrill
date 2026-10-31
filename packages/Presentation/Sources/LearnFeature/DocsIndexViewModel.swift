import Foundation
import Observation
import AppCore
import DomainModels
import DomainInterfaces

/// ドメイン目次(SCR-041)の1行。ドキュメントのないサブ項目は「準備中」で選べない
public struct DocsIndexRow: Hashable, Sendable, Identifiable {
    public var id: String
    public var name: LocalizedText
    /// ドキュメントのタイトル。nil なら準備中
    public var title: String?
    public var isAvailable: Bool { title != nil }
}

public struct DocsIndexSection: Hashable, Sendable, Identifiable {
    public var id: Int
    public var name: LocalizedText
    /// 試験定義でのドメインの位置(配色用)
    public var domainIndex: Int
    public var rows: [DocsIndexRow]
}

@MainActor @Observable public final class DocsIndexViewModel {
    /// 試験定義のドメインの順に、サブ項目の順で並べる(FR-DOCS-01)
    public let sections: [DocsIndexSection]
    public var isAvailable: Bool { content.definition.features.docs }
    private let content: any ExamContentProvider
    private let router: AppRouter

    public init(content: any ExamContentProvider, domain: Int? = nil, router: AppRouter) {
        self.content = content; self.router = router
        guard content.definition.features.docs else { sections = []; return }
        let titles = Dictionary(content.docsIndex.map { ($0.subObjective, $0.title) }, uniquingKeysWith: { first, _ in first })
        sections = content.definition.domains.enumerated().compactMap { index, definition in
            guard domain == nil || domain == definition.id else { return nil }
            return DocsIndexSection(id: definition.id, name: definition.name, domainIndex: index,
                rows: definition.subObjectives.map { DocsIndexRow(id: $0.id, name: $0.name, title: titles[$0.id]) })
        }
    }

    public func open(_ row: DocsIndexRow) {
        guard row.isAvailable else { return }
        router.open(.doc(subObjective: row.id))
    }
}
