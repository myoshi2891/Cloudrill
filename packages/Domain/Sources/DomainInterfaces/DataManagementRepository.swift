import Foundation
import DomainModels
public protocol DataManagementRepository: Sendable {
    func export(examID: ExamID?) async throws(PersistenceError) -> Data
    func deleteAll(examID: ExamID?) async throws(PersistenceError)
}
