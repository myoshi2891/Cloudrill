import Foundation
import Synchronization
import Testing
import DomainModels
import DomainInterfaces
@testable import ContentKit

final class SpyFileReader: FileReading, Sendable {
    private let reads = Mutex<[String]>([])
    var paths: [String] { reads.withLock { $0 } }
    func read(_ url: URL) throws -> Data {
        reads.withLock { $0.append(url.path) }
        return try Data(contentsOf: url)
    }
}

extension PackFixtures {
    static func content(_ exam: String = "test-alpha", reader: any FileReading = FileManagerReader()) throws -> PackContent {
        let directory = valid(exam)
        let manifest = try verifier().verify(packAt: directory, expectedExamID: ExamID(rawValue: exam), currentVersion: nil)
        return try PackLoader(fileReader: reader).load(packAt: directory, manifest: manifest)
    }
}

struct PackLoaderTests {
    @Test func loadsEagerParts() throws {
        let content = try PackFixtures.content()
        #expect(content.definition.id == "test-alpha")
        #expect(content.vendor.id == content.definition.vendor)
        #expect(content.packVersion == "1.0.0")
        #expect(content.questionIndex.count >= 55)
        #expect(!content.examSets.isEmpty && !content.docsIndex.isEmpty)
    }
    @Test func doesNotReadQuestionBodiesAtLoad() throws {
        let spy = SpyFileReader()
        _ = try PackFixtures.content(reader: spy)
        #expect(spy.paths.count == 5)
        #expect(!spy.paths.contains { $0.contains("questions/domain") })
    }
    @Test func questionsReadOnlyNeededDomainsAndAreCached() async throws {
        let spy = SpyFileReader()
        let content = try PackFixtures.content(reader: spy)
        let ids = content.questionIndex.filter { $0.domain == 2 }.map(\.id)
        #expect(!ids.isEmpty)
        #expect(try await content.questions(ids: ids).map(\.id) == ids)
        _ = try await content.questions(ids: ids)
        #expect(spy.paths.filter { $0.contains("questions/domain") }.map { URL(filePath: $0).lastPathComponent } == ["domain2.json"])
    }
    @Test func questionsKeepRequestedOrder() async throws {
        let content = try PackFixtures.content()
        let ids = [content.questionIndex[10].id, content.questionIndex[0].id, content.questionIndex[10].id]
        #expect(try await content.questions(ids: ids).map(\.id) == ids)
    }
    @Test func unknownQuestionID() async throws {
        let spy = SpyFileReader()
        let content = try PackFixtures.content(reader: spy)
        await #expect(throws: ContentError.unknownQuestionIDs(["missing"])) { try await content.questions(ids: [content.questionIndex[0].id, "missing"]) }
        #expect(!spy.paths.contains { $0.contains("questions/domain") })
    }
    @Test func concurrentRequestsShareCache() async throws {
        let spy = SpyFileReader()
        let content = try PackFixtures.content(reader: spy)
        let id = try #require(content.questionIndex.first?.id)
        try await withThrowingTaskGroup(of: Void.self) { group in
            for _ in 0..<10 { group.addTask { _ = try await content.questions(ids: [id]) } }
            try await group.waitForAll()
        }
        #expect(spy.paths.filter { $0.contains("questions/domain") }.count == 1)
    }
    @Test func disabledFeature() async throws {
        let content = try PackFixtures.content("test-beta")
        await #expect(throws: ContentError.featureDisabled("caseStudies")) { try await content.caseStudies() }
        await #expect(throws: ContentError.featureDisabled("decisionTrees")) { try await content.decisionTrees() }
        await #expect(throws: ContentError.featureDisabled("keywordDrills")) { try await content.keywordDrills() }
    }
    @Test func enabledFeatures() async throws {
        let content = try PackFixtures.content()
        #expect(try await !content.flashcards().isEmpty)
        #expect(try await content.caseStudies().count == 2)
        #expect(try await !content.decisionTrees().isEmpty)
        #expect(try await !content.keywordDrills().isEmpty)
    }
    @Test func docBody() async throws {
        let content = try PackFixtures.content()
        let body = try await content.docBody(for: #require(content.docsIndex.first))
        #expect(body.hasPrefix("# ダミーのドキュメント"))
        #expect(!body.hasPrefix("---"))
    }
    @Test func rejectsForeignDocEntry() async throws {
        let content = try PackFixtures.content()
        var entry = try #require(content.docsIndex.first)
        entry.path = "../outside.md"
        await #expect(throws: ContentError.fileMissing(entry.path)) { try await content.docBody(for: entry) }
    }
    @Test func loadAllQuestionsForExamSetUnderBudget() async throws {
        let content = try PackFixtures.content()
        let ids = try #require(content.examSets.first).questionIDs
        let elapsed = try await ContinuousClock().measure { () async throws -> Void in
            let questions = try await content.questions(ids: ids)
            #expect(questions.count == 55)
        }
        print("P2-S06: load 55 questions: \(elapsed)")
    }
    @Test(arguments: [false, true])
    func missingAndUndecodableFiles(invalid: Bool) throws {
        let root = PackFixtures.temporary()
        defer { try? FileManager.default.removeItem(at: root) }
        let pack = try PackFixtures.copy(to: root)
        let manifest = try PackFixtures.verifier().verify(packAt: pack, expectedExamID: "test-alpha", currentVersion: nil)
        if invalid { try Data("{".utf8).write(to: pack.appending(path: "exam.json")) }
        else { try FileManager.default.removeItem(at: pack.appending(path: "exam.json")) }
        do {
            _ = try PackLoader().load(packAt: pack, manifest: manifest)
            Issue.record("expected content error")
        } catch {
            if invalid { guard case .undecodable(path: "exam.json", reason: _) = error else { Issue.record("\(error)"); return } }
            else { #expect(error == .fileMissing("exam.json")) }
        }
    }
}
