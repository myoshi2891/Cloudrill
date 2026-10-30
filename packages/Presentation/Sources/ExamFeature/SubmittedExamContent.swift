import Foundation
import DomainModels
import DomainInterfaces
import ExamEngine

/// 結果と解説が同じ保存済み出題順・版を使うための読み込み境界。
struct SubmittedExamContent {
    let summary: AttemptSummary
    let content: any ExamContentProvider
    let questions: [Question]

    static func load(examID: ExamID, attemptID: UUID, attempts: any ExamAttemptRepository,
                     resolver: any ExamContentResolving) async throws -> Self {
        guard let summary = try await attempts.history(examID: examID).first(where: { $0.id == attemptID }),
              summary.attempt.examID == examID,
              summary.attempt.snapshot.state == .submitted(summary.reason) else { throw PersistenceError.notFound }
        let content = try await resolver.content(for: examID, version: summary.attempt.packVersion)
        guard content.definition.id == examID, content.packVersion == summary.attempt.packVersion else {
            throw ContentError.storage("attempt pack mismatch")
        }
        let order = summary.attempt.snapshot.order
        let ids = order.items.map(\.questionID)
        let loaded = try await content.questions(ids: ids)
        let byID = Dictionary(loaded.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
        guard !ids.isEmpty, Set(ids).count == ids.count, loaded.count == ids.count, byID.count == ids.count else {
            throw ContentError.storage("invalid submitted questions")
        }
        try ExamOrderBuilder.validate(order, against: byID)
        return Self(summary: summary, content: content, questions: ids.compactMap { byID[$0] })
    }
}
