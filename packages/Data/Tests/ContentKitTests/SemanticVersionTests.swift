import Testing
@testable import ContentKit

struct SemanticVersionTests {
    @Test(arguments: [
        ("1.0.0", "1.0.1"), ("1.0.1", "1.1.0"), ("1.1.0", "2.0.0"),
        ("1.0.0-alpha", "1.0.0"), ("1.0.0-alpha", "1.0.0-alpha.1"),
        ("1.0.0-alpha.1", "1.0.0-beta"), ("1.0.0-beta.2", "1.0.0-beta.11"),
        ("1.0.0-9", "1.0.0-a"), ("99999999999999999999.0.0", "100000000000000000000.0.0"),
    ])
    func ordering(left: String, right: String) throws {
        #expect(try #require(SemanticVersion(left)) < #require(SemanticVersion(right)))
    }
    @Test func buildMetadataDoesNotChangePrecedence() {
        #expect(SemanticVersion("1.0.0+build") == SemanticVersion("1.0.0"))
        #expect(Set([SemanticVersion("1.0.0+build"), SemanticVersion("1.0.0")]).count == 1)
    }
    @Test(arguments: ["1.0", "01.0.0", "v1.0.0", "1.0.0-01", "1.0.0-a..b", "1.0.0+a..b", "1.0.0-", "1.0.0\n"])
    func rejectsInvalid(value: String) { #expect(SemanticVersion(value) == nil) }
}
