import Foundation
import DomainModels

/// 受験が参照する版を、パックの削除対象から除外する。
public protocol PackPinning: Sendable {
    func pin(_ version: String, for examID: ExamID, attemptID: UUID) async throws(ContentError)
    func unpin(attemptID: UUID, for examID: ExamID) async throws(ContentError)
}
