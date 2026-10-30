import SwiftUI
import DomainModels

public struct ReferenceLink: View {
    private let reference: Reference
    public init(_ reference: Reference) { self.reference = reference }
    public var body: some View {
        Link(destination: reference.url) {
            VStack(alignment: .leading, spacing: 4) {
                Label(reference.title, systemImage: "arrow.up.right.square").font(.body)
                if let license = Self.licenseLabel(reference.license) { Text(license).font(.caption) }
            }
            .frame(minWidth: 44, minHeight: 44, alignment: .leading)
            .contentShape(Rectangle())
        }
        .accessibilityElement(children: .combine)
    }
    public nonisolated static func licenseLabel(_ license: License) -> String? {
        switch license {
        case .ccBy40: "CC BY 4.0"
        case .apache20: "Apache 2.0"
        case .linkOnly: nil
        }
    }
}
