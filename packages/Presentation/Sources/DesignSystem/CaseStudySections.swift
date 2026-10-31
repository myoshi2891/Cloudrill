import SwiftUI
import DomainModels

/// ケースの要約(List の中に置く)。解答中のシートと学ぶタブの詳細(SCR-044)で共有する。
/// 全文は転載せず、公式ページへのリンクを出す(LG-03)
public struct CaseStudySections: View {
    private let caseStudy: CaseStudy
    public init(_ caseStudy: CaseStudy) { self.caseStudy = caseStudy }
    public var body: some View {
        Section { Text(caseStudy.summary.ja) } header: { Text("case.summary", bundle: .module) }
        Section {
            ForEach(Array(caseStudy.businessRequirements.enumerated()), id: \.offset) { _, item in Text(item.ja) }
        } header: { Text("case.business", bundle: .module) }
        Section {
            ForEach(Array(caseStudy.technicalRequirements.enumerated()), id: \.offset) { _, item in Text(item.ja) }
        } header: { Text("case.technical", bundle: .module) }
        Section { Text(caseStudy.existingEnvironment.ja) } header: { Text("case.environment", bundle: .module) }
        Link(destination: caseStudy.officialURL) { Text("case.official", bundle: .module) }
            .accessibilityIdentifier("case-official")
    }
}
