import DomainModels

/// CI-09・CI-12 と同じ試験語彙の整合違反。Domain のインターフェースとして公開する。
public enum IntegrityViolation: Equatable, Sendable {
    case unknownDomain(questionID: String, domain: Int)
    case unknownSubObjective(questionID: String, subObjective: String)
    case subObjectiveDomainMismatch(questionID: String, subObjective: String, domain: Int)
    case unknownCaseStudy(questionID: String, caseStudy: CaseStudyID)
    case caseStudyFeatureDisabled(questionID: String)
    case unsupportedQuestionKind(QuestionKind)
    case questionKindNotAllowed(questionID: String, kind: QuestionKind)
    case missingQuestion(examSet: Int, questionID: String)
    case examSetCaseCountMismatch(examSet: Int, expected: Int, actual: Int)
    case unknownExamSetCase(examSet: Int, caseStudy: CaseStudyID)
    case unknownWAFPillar(questionID: String, pillar: WAFPillarID)
    case nonContiguousDomains
    case duplicateSubObjective(String)
}
