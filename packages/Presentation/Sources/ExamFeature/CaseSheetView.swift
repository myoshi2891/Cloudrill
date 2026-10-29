import SwiftUI
import DomainModels

public struct CaseSheetView: View {
    public let caseStudy: CaseStudy
    @Environment(\.dismiss) private var dismiss
    public init(caseStudy: CaseStudy) { self.caseStudy = caseStudy }
    public var body: some View {
        NavigationStack {
            List {
                Section { Text(caseStudy.summary.ja) } header: { Text("case.summary", bundle: .module) }
                Section {
                    ForEach(Array(caseStudy.businessRequirements.enumerated()), id: \.offset) { _, item in Text(item.ja) }
                } header: { Text("case.business", bundle: .module) }
                Section {
                    ForEach(Array(caseStudy.technicalRequirements.enumerated()), id: \.offset) { _, item in Text(item.ja) }
                } header: { Text("case.technical", bundle: .module) }
                Section { Text(caseStudy.existingEnvironment.ja) } header: { Text("case.environment", bundle: .module) }
                Link(destination: caseStudy.officialURL) { Text("case.official", bundle: .module) }
            }
            .navigationTitle(caseStudy.name.ja)
            .toolbar { Button { dismiss() } label: { Text("session.close", bundle: .module) } }
        }
    }
}
