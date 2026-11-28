import Foundation
import Testing
import DesignSystem

struct MarkdownLinkPolicyTests {
    private let policy = MarkdownLinkPolicy(allowedHosts: ["cloud.google.com"])

    private func links(in markdown: String, policy: MarkdownLinkPolicy) throws -> [URL] {
        let options = AttributedString.MarkdownParsingOptions(interpretedSyntax: .inlineOnlyPreservingWhitespace)
        let sanitized = policy.sanitized(try AttributedString(markdown: markdown, options: options))
        return sanitized.runs[\.link].compactMap { $0.0 }
    }

    @Test func allowedHTTPSLinkIsKept() throws {
        // Act
        let result = try links(in: "[x](https://cloud.google.com/docs)", policy: policy)
        // Assert
        #expect(result == [URL(string: "https://cloud.google.com/docs")])
    }

    @Test(arguments: [
        "[x](javascript:alert(1))",
        "[x](file:///etc/hosts)",
        "[x](tel:110)",
        "[x](http://cloud.google.com/docs)",
        "[x](https://unexpected.example/)",
        "[x](https://cloud.google.com.evil.example/)",
    ])
    func disallowedLinksAreRemovedButTextRemains(markdown: String) throws {
        // Arrange
        let options = AttributedString.MarkdownParsingOptions(interpretedSyntax: .inlineOnlyPreservingWhitespace)
        // Act
        let sanitized = policy.sanitized(try AttributedString(markdown: markdown, options: options))
        // Assert
        #expect(sanitized.runs[\.link].allSatisfy { $0.0 == nil })
        #expect(String(sanitized.characters) == "x")
    }

    @Test func defaultPolicyDeniesAllLinks() throws {
        #expect(try links(in: "[x](https://cloud.google.com/docs)", policy: .denyAll).isEmpty)
    }

    @Test func hostComparisonIgnoresCase() {
        #expect(MarkdownLinkPolicy(allowedHosts: ["Cloud.Google.com"]).permits(URL(string: "HTTPS://CLOUD.GOOGLE.COM/x")!))
    }
}
