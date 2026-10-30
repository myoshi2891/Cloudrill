import Foundation
import DomainModels

/// 受験が参照する版を、パックの削除対象から除外する。
public protocol PackPinning: Sendable {
    func pin(_ version: String, for examID: ExamID, attemptID: UUID) async throws(ContentError)
    /// 提出済みの受験の固定を、結果・解説を開くための保持へ移す。保持件数を超えた古い受験の固定は外れる。
    func retain(attemptID: UUID, for examID: ExamID) async throws(ContentError)
    func unpin(attemptID: UUID, for examID: ExamID) async throws(ContentError)
}
