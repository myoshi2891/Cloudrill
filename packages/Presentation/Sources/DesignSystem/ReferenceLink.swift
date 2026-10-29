import SwiftUI
import DomainModels

public struct ReferenceLink: View {
    private let reference: Reference
    public init(_ reference: Reference) { self.reference = reference }
    public var body: some View {
        Link(destination: reference.url) {
            VStack(alignment: .leading, spacing: 4) {
                Label(reference.title, systemImage: "arrow.up.right.square").font(.body)
                Text(reference.license.rawValue).font(.caption)
            }
            .frame(minWidth: 44, minHeight: 44, alignment: .leading)
            .contentShape(Rectangle())
        }
        .accessibilityElement(children: .combine)
    }
}
