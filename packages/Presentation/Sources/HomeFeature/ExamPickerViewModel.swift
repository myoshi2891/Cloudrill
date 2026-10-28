import Foundation
import Observation
import DomainModels
import AppCore

public struct ExamPickerItem: Equatable, Sendable, Identifiable {
    public let id: ExamID
    public let name: LocalizedText
    public let shortName: String
    public let status: CatalogStatus
    public let isSelectable: Bool
}
public struct ExamPickerState: Equatable, Sendable {
    public let items: [ExamPickerItem]
    public let selectedID: ExamID?
    public let trademarkNotice: LocalizedText?
    public let isLoading: Bool
    public let alert: AppAlert?
}

@MainActor @Observable public final class ExamPickerViewModel {
    private let context: ActiveExamContext
    public init(context: ActiveExamContext) { self.context = context }
    // 選択中の試験を二重管理せず、復元・切り替え後も同じ状態を表示する。
    public var state: ExamPickerState {
        ExamPickerState(items: context.catalog.filter { $0.status != .retired || context.isAvailable($0.id) }.map {
            ExamPickerItem(id: $0.id, name: $0.name, shortName: $0.shortName, status: $0.status,
                           isSelectable: context.isAvailable($0.id))
        }, selectedID: context.state.examID, trademarkNotice: context.content?.vendor.trademarkNotice,
           isLoading: context.state.isLoading, alert: context.state.alert)
    }
    public func select(_ id: ExamID) async { await context.switchExam(to: id) }
}
