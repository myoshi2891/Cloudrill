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
        try Storage.read {
            let rows = try PersistenceRows(context: modelContext, examID: examID?.rawValue)
            return try Storage.encode(rows.exportDocument())
        }
    }
    public func deleteAll(examID: ExamID?) throws(PersistenceError) {
        try Storage.write(modelContext, saver: saver) {
            try PersistenceRows(context: modelContext, examID: examID?.rawValue).deleteAll(in: modelContext)
        }
    }
}
