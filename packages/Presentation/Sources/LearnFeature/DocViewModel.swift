import Foundation
import Observation
import AppCore
import DomainModels
import DomainInterfaces
import DesignSystem

/// ドキュメント閲覧(SCR-042)。本文を中間表現に変換し、出典とライセンスを添える(FR-DOCS-02・06)
@MainActor @Observable public final class DocViewModel {
    public enum Phase: Equatable { case idle, loaded(MarkdownDocument), notFound, failed }
    public private(set) var phase: Phase = .idle
    public private(set) var isLoading = false
    public let subObjective: String
    /// 索引にあるドキュメント。ない(または docs が無効な)場合は nil
    public let entry: DocEntry?
    public var title: String { entry?.title ?? subObjective }
    public var references: [Reference] { entry?.references ?? [] }
    private let content: any ExamContentProvider

    public init(content: any ExamContentProvider, subObjective: String) {
        self.content = content; self.subObjective = subObjective
        entry = content.definition.features.docs ? content.docsIndex.first { $0.subObjective == subObjective } : nil
    }

    public func load() async {
        guard !isLoading else { return }
        if case .loaded = phase { return }
        guard let entry else { phase = .notFound; return }
        isLoading = true
        defer { isLoading = false }
        do {
            let body = try await content.docBody(for: entry)
            phase = .loaded(MarkdownDocument(parsing: body))
        } catch { phase = .failed }
    }
}
