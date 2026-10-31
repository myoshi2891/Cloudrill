import Testing
import DesignSystem

struct MarkdownDocumentTests {
    @Test(arguments: [
        ("# 見出し", MarkdownBlock.heading(level: 1, text: "見出し")),
        ("### 小見出し", .heading(level: 3, text: "小見出し")),
        ("本文の **強調** です。", .paragraph("本文の **強調** です。")),
        ("- a\n- b", .list(ordered: false, items: [[.paragraph("a")], [.paragraph("b")]])),
        ("1. a\n2. b", .list(ordered: true, items: [[.paragraph("a")], [.paragraph("b")]])),
        ("> 引用", .quote([.paragraph("引用")])),
        ("| 項目 | 値 |\n|---|---|\n| A | 1 |\n| B | 2 |", .table(header: ["項目", "値"], rows: [["A", "1"], ["B", "2"]])),
        ("```swift\nlet x = 1\n```", .code(language: "swift", code: "let x = 1")),
        ("```\nplain\n```", .code(language: nil, code: "plain")),
        ("![構成図](assets/x.svg)", .image(path: "assets/x.svg", alt: "構成図")),
        ("---", .thematicBreak),
    ])
    func markdownBlocks(source: String, expected: MarkdownBlock) {
        // Act
        let document = MarkdownDocument(parsing: source)
        // Assert
        #expect(document.blocks == [expected])
    }

    @Test func documentKeepsBlockOrder() {
        let document = MarkdownDocument(parsing: "# T\n\n段落\n\n- x\n")
        #expect(document.blocks == [.heading(level: 1, text: "T"), .paragraph("段落"), .list(ordered: false, items: [[.paragraph("x")]])])
    }

    @Test func unsupportedMarkdownFallsBack() {
        let document = MarkdownDocument(parsing: "<div class=\"note\">注意</div>\n\n後の段落")
        #expect(document.blocks == [.paragraph("<div class=\"note\">注意</div>"), .paragraph("後の段落")])
    }

    @Test func inlineImageStaysInParagraph() {
        let document = MarkdownDocument(parsing: "前 ![図](assets/x.svg) 後")
        guard case .paragraph(let text) = document.blocks.first else { Issue.record("段落になる"); return }
        #expect(text.contains("assets/x.svg"))
    }

    @Test(arguments: [
        ("assets/x.svg", "assets/x.svg"), ("./assets/x.svg", "assets/x.svg"), ("assets/%E5%9B%B3.png", "assets/図.png"),
    ])
    func imagesFromPackAssets(source: String, expected: String) {
        #expect(MarkdownDocument.packAssetPath(source) == expected)
    }

    @Test(arguments: ["../x.svg", "assets/../../x.svg", "%2e%2e/x.svg", "/etc/x.svg", "https://example.com/x.svg",
                      "file:///etc/x.svg", "", "assets//x.svg", "assets\\x.svg", ".",
                      "javascript%3Aalert(1)", "https%3A//example.com/x.svg", "%68ttps%3A%2F%2Fexample.com/x.svg"])
    func pathsOutsidePackAreHidden(source: String) {
        #expect(MarkdownDocument.packAssetPath(source) == nil)
        #expect(MarkdownDocument(parsing: "![x](\(source))").blocks.allSatisfy {
            if case .image(let path, _) = $0 { path == nil } else { true }
        })
    }
}
