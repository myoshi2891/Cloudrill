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
        render(ChoiceQuestionPresentation(question: question, choiceIDs: question.choices.map(\.id)), selected: selected, select: select)
    }

    @MainActor public func render(_ question: ChoiceQuestionPresentation, selected: Set<String>,
                                 select: @escaping (String) -> Void) -> some View {
        ChoiceQuestionRenderer(question: question, selected: selected, select: select)
    }
}
