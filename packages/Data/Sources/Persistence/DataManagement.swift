import Foundation
import SwiftData
import DomainModels
import DomainInterfaces
@ModelActor public actor DataManagement: DataManagementRepository {
    private var saver: any Saver = ContextSaver()
    public init(modelContainer: ModelContainer, saver: any Saver) {
        self.modelContainer = modelContainer
        self.modelExecutor = DefaultSerialModelExecutor(modelContext: ModelContext(modelContainer))
        self.saver = saver
    }
    public func export(examID: ExamID?) throws(PersistenceError) -> Data {
        Data(#"{"exportVersion":1,"schema":"V1","entities":{}}"#.utf8)
    }
    public func deleteAll(examID: ExamID?) throws(PersistenceError) {}
}
