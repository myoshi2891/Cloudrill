import Foundation
import Markdown

/// `MarkdownView` が描画に使う中間表現(FR-DOCS-02)。パースと描画を分け、変換だけをテストできるようにする。
/// インラインの強調・リンクは Markdown の文字列のまま持ち、描画時に `AttributedString` へ変換する。
public enum MarkdownBlock: Hashable, Sendable {
    case heading(level: Int, text: String)
    case paragraph(String)
    case list(ordered: Bool, items: [[MarkdownBlock]])
    case quote([MarkdownBlock])
    case table(header: [String], rows: [[String]])
    case code(language: String?, code: String)
    /// `path` はパックのルートからの相対パス。パックの外を指すパスは nil(表示しない)
    case image(path: String?, alt: String)
    case thematicBreak
}

public struct MarkdownDocument: Hashable, Sendable {
    public var blocks: [MarkdownBlock]

    public init(blocks: [MarkdownBlock]) { self.blocks = blocks }

    public init(parsing text: String) {
        blocks = Document(parsing: text).children.flatMap(Self.blocks(from:))
    }

    /// 画像の参照先を、パックのルートからの相対パスに解決する。
    /// スキーム付き・絶対パス・`..` や空の区切りを含むパスは nil。パーセントエンコードは解いてから確かめる。
    /// スキームは解いた後の先頭の区切りに `:` があるかで判定する(`javascript%3A...` も弾く)。
    public static func packAssetPath(_ source: String?) -> String? {
        guard let source, let decoded = source.removingPercentEncoding, !decoded.isEmpty,
              !decoded.hasPrefix("/"), !decoded.contains("\\") else { return nil }
        let parts = decoded.split(separator: "/", omittingEmptySubsequences: false)
        guard let first = parts.first, !first.contains(":"),
              !parts.contains(where: { $0 == ".." || $0.isEmpty }) else { return nil }
        let normalized = parts.filter { $0 != "." }
        return normalized.isEmpty ? nil : normalized.joined(separator: "/")
    }

    private static func blocks(from markup: any Markup) -> [MarkdownBlock] {
        switch markup {
        case let heading as Heading:
            return [.heading(level: heading.level, text: inline(heading))]
        case let paragraph as Paragraph:
            // 画像だけの段落は画像のブロックにする。文中の画像は段落のインラインのまま描画する
            let content = paragraph.children.filter { !($0 is SoftBreak || $0 is LineBreak) }
            let images = content.compactMap { $0 as? Image }
            if !images.isEmpty, images.count == content.count {
                return images.map { .image(path: packAssetPath($0.source), alt: $0.plainText) }
            }
            return [.paragraph(inline(paragraph))]
        case let list as UnorderedList:
            return [.list(ordered: false, items: items(of: list))]
        case let list as OrderedList:
            return [.list(ordered: true, items: items(of: list))]
        case let quote as BlockQuote:
            return [.quote(quote.children.flatMap(blocks(from:)))]
        case let table as Table:
            let header = Array(table.head.cells.map(inline))
            let rows = table.body.rows.map { Array($0.cells.map(inline)) }
            return [.table(header: header, rows: Array(rows))]
        case let code as CodeBlock:
            let body = code.code.hasSuffix("\n") ? String(code.code.dropLast()) : code.code
            return [.code(language: code.language, code: body)]
        case is ThematicBreak:
            return [.thematicBreak]
        case let html as HTMLBlock:
            // HTML は解釈せず、元の文字列を段落として出す
            let raw = html.rawHTML.trimmingCharacters(in: .whitespacesAndNewlines)
            return raw.isEmpty ? [] : [.paragraph(raw)]
        default:
            // 未対応のブロックも落とさず、元の Markdown を段落として出す
            let raw = markup.detachedFromParent.format().trimmingCharacters(in: .whitespacesAndNewlines)
            return raw.isEmpty ? [] : [.paragraph(raw)]
        }
    }

    private static func items(of list: any Markup) -> [[MarkdownBlock]] {
        list.children.compactMap { $0 as? ListItem }.map { $0.children.flatMap(blocks(from:)) }
    }

    /// format() は祖先(引用・リスト)の記号も付けるため、親から切り離して整形する
    private static func inline(_ markup: any Markup) -> String {
        markup.children.map { $0.detachedFromParent.format() }.joined().trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
