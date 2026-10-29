import SwiftUI
import DomainModels

public struct DomainBadge: View {
    private let index: Int
    private let title: String
    @Environment(\.colorScheme) private var scheme

    public init(index: Int, title: String) { self.index = index; self.title = title }

    public var body: some View {
        let style = DomainPalette.style(forDomainAt: index)
        Text("\(style.symbol) \(title)")
            .font(.caption.weight(.semibold))
            .foregroundStyle(style.foreground(for: scheme))
            .padding(8)
            .background(StudyColors.surface(for: scheme), in: RoundedRectangle(cornerRadius: 8))
            .accessibilityLabel(title)
    }
}

public struct CaseBadge: View {
    private let title: String
    public init(title: String) { self.title = title }
    public var body: some View { Label(title, systemImage: "doc.text").font(.caption).padding(8) }
}

public struct ResultBadge: View {
    private let isCorrect: Bool
    @Environment(\.colorScheme) private var scheme
    public init(isCorrect: Bool) { self.isCorrect = isCorrect }
    public nonisolated static func symbolName(isCorrect: Bool) -> String {
        isCorrect ? "checkmark.circle.fill" : "xmark.circle.fill"
    }
    public nonisolated static func title(isCorrect: Bool) -> String {
        String(localized: isCorrect ? "result.correct" : "result.incorrect", bundle: .module)
    }
    public var body: some View {
        Label(Self.title(isCorrect: isCorrect), systemImage: Self.symbolName(isCorrect: isCorrect))
            .font(.body.weight(.semibold))
            .foregroundStyle(StudyColors.result(isCorrect: isCorrect, scheme: scheme))
            .padding(8)
            .background(StudyColors.surface(for: scheme), in: RoundedRectangle(cornerRadius: 8))
    }
}

public struct MistakeTagChip: View {
    private let tag: MistakeTag
    public init(_ tag: MistakeTag) { self.tag = tag }
    public nonisolated static func title(for tag: MistakeTag) -> String {
        switch tag {
        case .cost: String(localized: "mistake.cost", bundle: .module)
        case .opsOverhead: String(localized: "mistake.opsOverhead", bundle: .module)
        case .compliance: String(localized: "mistake.compliance", bundle: .module)
        case .scalability: String(localized: "mistake.scalability", bundle: .module)
        case .availability: String(localized: "mistake.availability", bundle: .module)
        case .latency: String(localized: "mistake.latency", bundle: .module)
        case .requirementMismatch: String(localized: "mistake.requirementMismatch", bundle: .module)
        case .deprecated: String(localized: "mistake.deprecated", bundle: .module)
        }
    }
    public nonisolated static func symbolName(for tag: MistakeTag) -> String {
        switch tag {
        case .cost: "yensign.circle"
        case .opsOverhead: "wrench.and.screwdriver"
        case .compliance: "checkmark.shield"
        case .scalability: "arrow.up.right"
        case .availability: "server.rack"
        case .latency: "clock"
        case .requirementMismatch: "exclamationmark.triangle"
        case .deprecated: "archivebox"
        }
    }
    public var body: some View {
        Label(Self.title(for: tag), systemImage: Self.symbolName(for: tag))
            .font(.caption).padding(8)
            .background(.quaternary, in: RoundedRectangle(cornerRadius: 8))
    }
}
