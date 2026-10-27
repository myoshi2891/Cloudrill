import DomainModels
import DomainInterfaces

public struct ContentIntegrityChecker: Sendable {
    private let supportedKinds: Set<QuestionKind>
    /// アプリが AnswerEvaluatorRegistry から渡す。ContentKit は ExamEngine に依存しない。
    public init(supportedKinds: Set<QuestionKind>) { self.supportedKinds = supportedKinds }

    public func check(_ content: PackContent) -> [IntegrityViolation] {
        let definition = content.definition
        var violations: [IntegrityViolation] = []
        // CI-12: ドメイン連番、サブ項目の一意性。
        if definition.domains.map(\.id).sorted() != Array(0..<definition.domains.count).map({ $0 + 1 }) {
            violations.append(.nonContiguousDomains)
        }
        var subObjectives: Set<String> = []
        for sub in definition.domains.flatMap(\.subObjectives) where !subObjectives.insert(sub.id).inserted {
            violations.append(.duplicateSubObjective(sub.id))
        }
        // CI-12: 出題形式はアプリが対応するものに限る。
        let kinds = Set(definition.format.questionKinds).union(content.questionIndex.map(\.kind))
        for kind in kinds.sorted(by: { $0.rawValue < $1.rawValue }) where !supportedKinds.contains(kind) {
            violations.append(.unsupportedQuestionKind(kind))
        }
        for entry in content.questionIndex {
            violations += checkVocabulary(id: entry.id, domain: entry.domain, subObjective: entry.subObjective,
                caseStudy: entry.caseStudy, kind: entry.kind, definition: definition)
        }
        // CI-09 / CI-02: 模試の問題・ケース参照とケース数。
        let questionIDs = Set(content.questionIndex.map(\.id))
        let caseIDs = Set(definition.caseStudies)
        let count = definition.features.caseStudies ? definition.format.mockExam.caseStudiesPerSet : 0
        for examSet in content.examSets {
            for id in examSet.questionIDs where !questionIDs.contains(id) {
                violations.append(.missingQuestion(examSet: examSet.id, questionID: id))
            }
            for id in examSet.caseStudies where !caseIDs.contains(id) {
                violations.append(.unknownExamSetCase(examSet: examSet.id, caseStudy: id))
            }
            if examSet.caseStudies.count != count {
                violations.append(.examSetCaseCountMismatch(examSet: examSet.id, expected: count, actual: examSet.caseStudies.count))
            }
        }
        return violations
    }

    public func check(questions: [Question], in definition: ExamDefinition) -> [IntegrityViolation] {
        // CI-09: 本文を読むときに、索引にない WAF の柱も確認する。
        let pillars = Set(definition.taxonomies.wafPillars.map(\.id))
        return questions.flatMap { question in
            var result = checkVocabulary(id: question.id, domain: question.domain, subObjective: question.subObjective,
                caseStudy: question.caseStudy, kind: question.type.kind, definition: definition)
            if !supportedKinds.contains(question.type.kind) { result.append(.unsupportedQuestionKind(question.type.kind)) }
            for pillar in question.wafPillars where !pillars.contains(pillar) {
                result.append(.unknownWAFPillar(questionID: question.id, pillar: pillar))
            }
            return result
        }
    }

    private func checkVocabulary(id: String, domain: Int, subObjective: String, caseStudy: CaseStudyID?, kind: QuestionKind,
                                 definition: ExamDefinition) -> [IntegrityViolation] {
        var result: [IntegrityViolation] = []
        // CI-09: domain / subObjective / caseStudy は試験定義の語彙に属する。
        if !definition.domains.contains(where: { $0.id == domain }) { result.append(.unknownDomain(questionID: id, domain: domain)) }
        if let expected = definition.domainBySubObjective[subObjective] {
            if expected != domain { result.append(.subObjectiveDomainMismatch(questionID: id, subObjective: subObjective, domain: domain)) }
        } else { result.append(.unknownSubObjective(questionID: id, subObjective: subObjective)) }
        if let caseStudy, !definition.caseStudies.contains(caseStudy) { result.append(.unknownCaseStudy(questionID: id, caseStudy: caseStudy)) }
        // CI-12: 無効なケース機能と、試験が許可しない出題形式を拒否する。
        if caseStudy != nil && !definition.features.caseStudies { result.append(.caseStudyFeatureDisabled(questionID: id)) }
        if !definition.format.questionKinds.contains(kind) { result.append(.questionKindNotAllowed(questionID: id, kind: kind)) }
        return result
    }
}
