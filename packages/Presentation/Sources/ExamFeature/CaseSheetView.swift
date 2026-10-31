import SwiftUI
import DomainModels
import DesignSystem

public struct CaseSheetView: View {
    public let caseStudy: CaseStudy
    @Environment(\.dismiss) private var dismiss
    public init(caseStudy: CaseStudy) { self.caseStudy = caseStudy }
    public var body: some View {
        NavigationStack {
            List { CaseStudySections(caseStudy) }
                .navigationTitle(caseStudy.name.ja)
                .toolbar { Button { dismiss() } label: { Text("session.close", bundle: .module) } }
        }
    }
}
