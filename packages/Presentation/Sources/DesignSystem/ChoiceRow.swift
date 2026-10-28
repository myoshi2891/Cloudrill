import SwiftUI

public struct ChoiceRow: View {
    public let id: String
    public let text: String
    public let isSelected: Bool
    private let action: () -> Void
    @Environment(\.dynamicTypeSize) private var typeSize

    public init(id: String, text: String, isSelected: Bool, action: @escaping () -> Void) {
        self.id = id; self.text = text; self.isSelected = isSelected; self.action = action
    }

    public nonisolated static func accessibilityLabel(for id: String, isSelected: Bool) -> String {
        let format = String(localized: isSelected ? "choice.selected" : "choice.unselected", bundle: .module)
        return String(format: format, id)
    }

    public var body: some View {
        Button(action: action) {
            let layout = typeSize.isAccessibilitySize ? AnyLayout(VStackLayout(alignment: .leading, spacing: 8))
                : AnyLayout(HStackLayout(alignment: .top, spacing: 12))
            layout {
                Label(id, systemImage: isSelected ? "checkmark.circle.fill" : "circle")
                    .font(.headline)
                Text(text).font(.body).fixedSize(horizontal: false, vertical: true)
            }
            .padding(12)
            .frame(minWidth: 44, maxWidth: .infinity, minHeight: 44, alignment: .leading)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .overlay(RoundedRectangle(cornerRadius: 12).strokeBorder(isSelected ? Color.primary : Color.secondary,
                                                               lineWidth: isSelected ? 2 : 1))
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Self.accessibilityLabel(for: id, isSelected: isSelected) + "、" + text)
        .accessibilityAddTraits(isSelected ? [.isSelected] : [])
    }
}
