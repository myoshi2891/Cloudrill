import Foundation
import SwiftData

/// 誤り報告の送信キューのスキーマ。学習履歴(SchemaV1)と別のストアに置き、CloudKit で同期しない。
/// 同期すると端末ごとに同じ報告を送信し、自由記述も iCloud に複製されるため(BDD 7.2 の端末内キュー)。
public enum ReportQueueSchemaV1: VersionedSchema {
    public static var versionIdentifier: Schema.Version { Schema.Version(1, 0, 0) }
    public static var models: [any PersistentModel.Type] { [PendingReport.self] }

    @Model public final class PendingReport {
        public var id: UUID = UUID()
        public var examID: String = ""
        public var questionID: String = ""
        public var questionRevision: Int = 0
        public var packVersion: String = ""
        public var reasonRaw: String = ""
        public var comment: String = ""
        public var appVersion: String = ""
        public var locale: String = ""
        public var createdAt: Date = Date.distantPast
        public init() {}
    }
}

public enum ReportQueueMigrationPlan: SchemaMigrationPlan {
    public static var schemas: [any VersionedSchema.Type] { [ReportQueueSchemaV1.self] }
    public static var stages: [MigrationStage] { [] }
}

/// 学習履歴と同じ保存先ディレクトリに、別ファイル `ReportQueue.store` を作る。
public enum ReportQueueContainerFactory {
    static let storeFileName = "ReportQueue.store"

    public static func make(inMemory: Bool, storeDirectory: URL? = nil) throws -> ModelContainer {
        let schema = Schema(versionedSchema: ReportQueueSchemaV1.self)
        let configuration: ModelConfiguration
        if inMemory {
            configuration = ModelConfiguration("ReportQueue", schema: schema, isStoredInMemoryOnly: true,
                                               groupContainer: .none, cloudKitDatabase: .none)
        } else {
            guard let storeDirectory else { throw ModelContainerFactoryError.storeDirectoryRequired }
            guard storeDirectory.isFileURL else { throw ModelContainerFactoryError.invalidStoreDirectory }
            try FileManager.default.createDirectory(at: storeDirectory, withIntermediateDirectories: true)
            configuration = ModelConfiguration("ReportQueue", schema: schema, url: storeDirectory.appending(path: storeFileName),
                                               cloudKitDatabase: .none)
        }
        return try ModelContainer(for: schema, migrationPlan: ReportQueueMigrationPlan.self, configurations: [configuration])
    }
}
