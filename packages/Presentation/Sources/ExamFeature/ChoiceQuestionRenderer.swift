import SwiftUI
import DesignSystem

public struct ChoiceQuestionRenderer: View {
    public let question: ChoiceQuestionPresentation
    public let selected: Set<String>
    public let select: (String) -> Void

    public var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text(question.stem).accessibilityIdentifier("session-stem")
            Text(String(format: String(localized: "session.required", bundle: .module), question.requiredSelections))
                .font(.subheadline).accessibilityIdentifier("session-required")
            ForEach(question.choices) { choice in
                ChoiceRow(id: choice.id, text: choice.text, isSelected: selected.contains(choice.id)) { select(choice.id) }
                    .accessibilityIdentifier("session-choice-\(choice.id)")
            }
        }
    }
}
