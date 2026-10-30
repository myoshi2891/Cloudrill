import DomainModels

/// 受験開始時の版を解決する。最新版への置き換えは行わない。
public protocol ExamContentResolving: Sendable {
    func content(for examID: ExamID, version: String) async throws(ContentError) -> any ExamContentProvider
}
