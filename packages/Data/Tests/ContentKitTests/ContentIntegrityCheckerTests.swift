import Foundation
import Testing
import DomainModels
import DomainInterfaces
@testable import ContentKit

struct ContentIntegrityCheckerTests {
    let checker = ContentIntegrityChecker(supportedKinds: [.single, .multiple])
    private func edited(_ exam: String = "test-alpha", _ mutate: (inout ExamDefinition, inout [QuestionIndexEntry], inout [ExamSet]) -> Void) throws -> PackContent {
        let base = try PackFixtures.content(exam)
        var definition = base.definition, index = base.questionIndex, sets = base.examSets
        mutate(&definition, &index, &sets)
        return PackContent(definition: definition, vendor: base.vendor, packVersion: base.packVersion,
            questionIndex: index, examSets: sets, docsIndex: base.docsIndex,
            files: PackFiles(root: PackFixtures.valid(exam), reader: FileManagerReader()))
    }
    @Test(arguments: ["test-alpha", "test-beta"])
    func validPacksHaveNoViolations(exam: String) throws { #expect(try checker.check(PackFixtures.content(exam)).isEmpty) }
    @Test func unknownDomain() throws {
        let content = try edited { _, index, _ in index[0].domain = 9 }
        #expect(checker.check(content).contains(.unknownDomain(questionID: content.questionIndex[0].id, domain: 9)))
    }
    @Test func subObjectiveInWrongDomain() throws {
        let content = try edited { _, index, _ in index[0].subObjective = "2.1" }
        #expect(checker.check(content).contains(.subObjectiveDomainMismatch(questionID: content.questionIndex[0].id, subObjective: "2.1", domain: 1)))
    }
    @Test func unknownCaseStudy() throws {
        let content = try edited { _, index, _ in index[0].caseStudy = "acmeBank" }
        #expect(checker.check(content).contains(.unknownCaseStudy(questionID: content.questionIndex[0].id, caseStudy: "acmeBank")))
    }
    @Test func caseStudyWhenDisabled() throws {
        let content = try edited("test-beta") { _, index, _ in index[0].caseStudy = "ehr" }
        #expect(checker.check(content).contains(.caseStudyFeatureDisabled(questionID: content.questionIndex[0].id)))
    }
    @Test func unsupportedKind() throws {
        let content = try PackFixtures.content()
        #expect(ContentIntegrityChecker(supportedKinds: [.single]).check(content).contains(.unsupportedQuestionKind(.multiple)))
    }
    @Test func kindNotAllowedByExam() throws {
        let content = try edited("test-beta") { _, index, _ in index[0].kind = .multiple }
        #expect(checker.check(content).contains(.questionKindNotAllowed(questionID: content.questionIndex[0].id, kind: .multiple)))
    }
    @Test func examSetReferencesMissingQuestion() throws {
        let content = try edited { _, _, sets in sets[0].questionIDs.append("missing") }
        #expect(checker.check(content).contains(.missingQuestion(examSet: 1, questionID: "missing")))
    }
    @Test func examSetCaseCount() throws {
        let content = try edited { _, _, sets in sets[0].caseStudies.removeLast() }
        #expect(checker.check(content).contains(.examSetCaseCountMismatch(examSet: 1, expected: 2, actual: 1)))
    }
    @Test func unknownWAFPillar() async throws {
        let content = try PackFixtures.content()
        var questions = try await content.questions(ids: [content.questionIndex[0].id])
        questions[0].wafPillars = ["resilience"]
        #expect(checker.check(questions: questions, in: content.definition) == [.unknownWAFPillar(questionID: questions[0].id, pillar: "resilience")])
    }
    @Test func unknownSubObjective() throws {
        let content = try edited { _, index, _ in index[0].subObjective = "unknown" }
        #expect(checker.check(content).contains(.unknownSubObjective(questionID: content.questionIndex[0].id, subObjective: "unknown")))
    }
    @Test func unknownExamSetCase() throws {
        let content = try edited { _, _, sets in sets[0].caseStudies[0] = "unknown" }
        #expect(checker.check(content).contains(.unknownExamSetCase(examSet: 1, caseStudy: "unknown")))
    }
    @Test func malformedDefinition() throws {
        let content = try edited { definition, _, _ in
            definition.domains[0].id = 9
            definition.domains[1].subObjectives.append(definition.domains[0].subObjectives[0])
        }
        let violations = checker.check(content)
        #expect(violations.contains(.nonContiguousDomains))
        #expect(violations.contains(.duplicateSubObjective("1.1")))
    }
    @Test func startupDoesNotReadBodies() throws {
        let spy = SpyFileReader()
        let content = try PackFixtures.content(reader: spy)
        #expect(checker.check(content).isEmpty)
        #expect(spy.paths.count == 5)
    }
}
