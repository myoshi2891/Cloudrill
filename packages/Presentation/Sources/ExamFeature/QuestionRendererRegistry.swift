import SwiftUI
import DomainModels

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
                Button { select(choice.id) } label: {
                    Label(choice.text.ja, systemImage: selected.contains(choice.id) ? "checkmark.circle.fill" : "circle")
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                .accessibilityAddTraits(selected.contains(choice.id) ? [.isSelected] : [])
            }
        }
    }
}
