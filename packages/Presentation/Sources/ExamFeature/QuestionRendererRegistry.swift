import SwiftUI
import DomainModels
import DesignSystem

/// 正誤を表示しない解答用レンダラー。選択制約はセッション側で管理する。
public struct QuestionRendererRegistry: Sendable {
    public static let standard = Self()
    public let supportedKinds: Set<QuestionKind> = [.single, .multiple]
    private init() {}

    @MainActor public func render(_ question: Question, selected: Set<String>,
                                 select: @escaping (String) -> Void) -> some View {
        VStack(alignment: .leading, spacing: 16) {
            Text(question.stem.ja)
            ForEach(question.choices) { choice in
                ChoiceRow(id: choice.id, text: choice.text.ja, isSelected: selected.contains(choice.id)) {
                    select(choice.id)
                }
            }
        }
    }
}
