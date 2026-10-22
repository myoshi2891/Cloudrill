import Foundation
import DomainModels

/// テスト用の試験定義。P0 の fixture の2試験と同じ形を既定値にし、テストに関係する値だけを `with` で変える。
/// ここの数値(120 分、55 問など)はテストデータで、Domain 層のコードには試験の値を書かない(DDD 4.1 X-01)。
public struct ExamDefinitionBuilder: Sendable {
    public var definition: ExamDefinition

    public init(_ definition: ExamDefinition) { self.definition = definition }

    public func with<Value>(_ keyPath: WritableKeyPath<ExamDefinition, Value>, _ value: Value) -> Self {
        var copy = self
        copy.definition[keyPath: keyPath] = value
        return copy
    }

    public func build() -> ExamDefinition { definition }

    /// fixture の test-alpha と同じ形: ドメイン 6、120 分、模試 55 問、ケース 2 件/回、single と multiple、すべての機能
    public static func alphaLike() -> Self {
        Self(ExamDefinition(
            id: "test-alpha",
            vendor: "test-vendor",
            name: LocalizedText(ja: "テスト試験 Alpha", en: "Test exam Alpha"),
            shortName: "ALPHA",
            guideVersion: "6.1",
            guideURL: URL(string: "https://example.com/certification/alpha")!,
            format: ExamFormat(
                durationMinutes: 120,
                officialQuestionCount: CountRange(min: 50, max: 60),
                questionKinds: [.single, .multiple],
                mockExam: MockExamFormat(questionCount: 55, setCount: 6, caseStudiesPerSet: 2)
            ),
            scoring: ScoringConfig(policy: .allOrNothing),
            domains: [
                domain(1, weight: 0.25, subObjectives: ["1.1", "1.2", "1.3", "1.4", "1.5"]),
                domain(2, weight: 0.18, subObjectives: ["2.1", "2.2", "2.3", "2.4", "2.5"]),
                domain(3, weight: 0.19, subObjectives: ["3.1", "3.2"]),
                domain(4, weight: 0.15, subObjectives: ["4.1", "4.2", "4.3"]),
                domain(5, weight: 0.115, subObjectives: ["5.1", "5.2"]),
                domain(6, weight: 0.115, subObjectives: ["6.1", "6.2", "6.3", "6.4", "6.5", "6.6"]),
            ],
            features: ExamFeatures(caseStudies: true, docs: true, flashcards: true, decisionTrees: true, keywordDrills: true),
            taxonomies: ExamTaxonomies(wafPillars: pillars([
                "operationalExcellence", "security", "reliability", "costOptimization", "performance", "sustainability",
            ])),
            caseStudies: ["case-a", "case-b"]
        ))
    }

    /// fixture の test-beta と同じ形: ドメイン 4、90 分、模試 40 問、ケースなし、single のみ、docs と flashcards のみ。
    /// ドメイン 2 のサブ項目はドメイン番号で始まらない(接頭辞でドメインを判定していないことを確かめるため)。
    public static func betaLike() -> Self {
        Self(ExamDefinition(
            id: "test-beta",
            vendor: "example-cloud",
            name: LocalizedText(ja: "テスト試験 Beta", en: "Test exam Beta"),
            shortName: "BETA",
            guideVersion: "1.0",
            guideURL: URL(string: "https://example.com/certification/beta")!,
            format: ExamFormat(
                durationMinutes: 90,
                officialQuestionCount: CountRange(min: 40, max: 50),
                questionKinds: [.single],
                mockExam: MockExamFormat(questionCount: 40, setCount: 2, caseStudiesPerSet: 0)
            ),
            scoring: ScoringConfig(policy: .allOrNothing),
            domains: [
                domain(1, weight: 0.3, subObjectives: ["1.1", "1.2"]),
                domain(2, weight: 0.3, subObjectives: ["NET.1", "NET.2"]),
                domain(3, weight: 0.2, subObjectives: ["3.1"]),
                domain(4, weight: 0.2, subObjectives: ["4.1"]),
            ],
            features: ExamFeatures(caseStudies: false, docs: true, flashcards: true, decisionTrees: false, keywordDrills: false),
            taxonomies: ExamTaxonomies(wafPillars: pillars(["resilience", "efficiency", "governance"])),
            caseStudies: []
        ))
    }

    private static func domain(_ id: Int, weight: Double, subObjectives: [String]) -> DomainDefinition {
        DomainDefinition(
            id: id,
            name: LocalizedText(ja: "ダミーのドメイン \(id)", en: "Dummy domain \(id)"),
            weight: weight,
            subObjectives: subObjectives.map {
                SubObjectiveDefinition(id: $0, name: LocalizedText(ja: "ダミーのサブ項目 \($0)", en: "Dummy sub-objective \($0)"))
            }
        )
    }

    private static func pillars(_ ids: [String]) -> [TaxonomyEntry<WAFPillarID>] {
        ids.map { TaxonomyEntry(id: WAFPillarID(rawValue: $0), name: LocalizedText(ja: "ダミーの柱 \($0)", en: "Dummy pillar \($0)")) }
    }
}
