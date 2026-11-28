import SwiftUI

/// `MarkdownDocument` を SwiftUI で描画する。パックの画像はまだ同梱されないため、代替テキストを表示する。
public struct MarkdownView: View {
    private let document: MarkdownDocument
    public init(document: MarkdownDocument) { self.document = document }
    public var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            ForEach(Array(document.blocks.enumerated()), id: \.offset) { _, block in
                BlockView(block: block)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

private struct BlockView: View {
    let block: MarkdownBlock
    var body: some View {
        switch block {
        case .heading(let level, let text):
            InlineText(text).font(Self.font(level: level)).accessibilityAddTraits(.isHeader)
        case .paragraph(let text):
            InlineText(text)
        case .list(let ordered, let items):
            VStack(alignment: .leading, spacing: 6) {
                ForEach(Array(items.enumerated()), id: \.offset) { index, item in
                    HStack(alignment: .firstTextBaseline, spacing: 8) {
                        Text(ordered ? "\(index + 1)." : "•").accessibilityHidden(true)
                        VStack(alignment: .leading, spacing: 6) {
                            ForEach(Array(item.enumerated()), id: \.offset) { _, child in BlockView(block: child) }
                        }
                    }
                }
            }
        case .quote(let children):
            VStack(alignment: .leading, spacing: 6) {
                ForEach(Array(children.enumerated()), id: \.offset) { _, child in BlockView(block: child) }
            }
            .padding(.leading, 12)
            .overlay(alignment: .leading) { Rectangle().fill(.secondary).frame(width: 3) }
            .foregroundStyle(.secondary)
        case .table(let header, let rows):
            ScrollView(.horizontal) {
                Grid(alignment: .leading, horizontalSpacing: 16, verticalSpacing: 8) {
                    GridRow { ForEach(Array(header.enumerated()), id: \.offset) { _, cell in InlineText(cell).bold() } }
                    Divider()
                    ForEach(Array(rows.enumerated()), id: \.offset) { _, row in
                        GridRow { ForEach(Array(row.enumerated()), id: \.offset) { _, cell in InlineText(cell) } }
                    }
                }.padding(8)
            }
        case .code(_, let code):
            ScrollView(.horizontal) {
                Text(code).font(.system(.callout, design: .monospaced)).textSelection(.enabled).padding(12)
            }
            .background(.quaternary, in: RoundedRectangle(cornerRadius: 8))
        case .image(let path, let alt):
            if path != nil {
                Label { Text(alt.isEmpty ? String(localized: "markdown.image", bundle: .module) : alt) }
                    icon: { Image(systemName: "photo") }
                    .font(.callout).foregroundStyle(.secondary)
            }
        case .thematicBreak:
            Divider()
        }
    }
    private static func font(level: Int) -> Font {
        switch level {
        case 1: .title2.bold()
        case 2: .title3.bold()
        default: .headline
        }
    }
}

/// 本文内のリンクの許可方針(SEC-05-06)。https で、許可したホストへのリンクだけを開ける。
/// 許可するホストの一覧は未決(SEC-05 未決事項 1)のため、既定は空で、すべてのリンクを開かない。
public struct MarkdownLinkPolicy: Sendable, Equatable {
    public let allowedHosts: Set<String>
    public init(allowedHosts: Set<String>) { self.allowedHosts = Set(allowedHosts.map { $0.lowercased() }) }
    public static let denyAll = MarkdownLinkPolicy(allowedHosts: [])

    public func permits(_ url: URL) -> Bool {
        guard url.scheme?.lowercased() == "https", let host = url.host()?.lowercased(), !host.isEmpty else { return false }
        return allowedHosts.contains(host)
    }

    /// 許可しないリンクの属性を外す。文字列はそのまま残し、タップしても開かない
    public func sanitized(_ attributed: AttributedString) -> AttributedString {
        var result = attributed
        for (link, range) in attributed.runs[\.link] {
            guard let link, !permits(link) else { continue }
            result[range].link = nil
        }
        return result
    }
}

private struct MarkdownLinkPolicyKey: EnvironmentKey {
    static let defaultValue = MarkdownLinkPolicy.denyAll
}

extension EnvironmentValues {
    public var markdownLinkPolicy: MarkdownLinkPolicy {
        get { self[MarkdownLinkPolicyKey.self] }
        set { self[MarkdownLinkPolicyKey.self] = newValue }
    }
}

/// インラインの Markdown(強調・リンク・コード)。解釈できなければ元の文字列を出す
private struct InlineText: View {
    @Environment(\.markdownLinkPolicy) private var linkPolicy
    private let source: String
    init(_ source: String) { self.source = source }
    var body: Text {
        let options = AttributedString.MarkdownParsingOptions(interpretedSyntax: .inlineOnlyPreservingWhitespace)
        if let attributed = try? AttributedString(markdown: source, options: options) { return Text(linkPolicy.sanitized(attributed)) }
        return Text(source)
    }
}
