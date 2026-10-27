import Foundation
import SwiftData

public enum ModelContainerFactoryError: Error, Equatable, Sendable {
    case storeDirectoryRequired
    case invalidStoreDirectory
}

/// App Group の保存先 URL はアプリ側で解決して渡す。
/// インメモリのストアは CloudKit を使わず、ディスクには書き込まない。
public enum ModelContainerFactory {
    public static func make(
        inMemory: Bool,
        cloudKitContainer: String?,
        storeDirectory: URL? = nil
    ) throws -> ModelContainer {
        let schema = Schema(versionedSchema: SchemaV1.self)
        let configuration: ModelConfiguration
        if inMemory {
            configuration = ModelConfiguration(
                "StudyHistory", schema: schema, isStoredInMemoryOnly: true,
                groupContainer: .none, cloudKitDatabase: .none
            )
        } else {
            guard let storeDirectory else { throw ModelContainerFactoryError.storeDirectoryRequired }
            guard storeDirectory.isFileURL else { throw ModelContainerFactoryError.invalidStoreDirectory }
            try FileManager.default.createDirectory(at: storeDirectory, withIntermediateDirectories: true)
            configuration = ModelConfiguration(
                "StudyHistory", schema: schema, url: storeDirectory.appending(path: "StudyHistory.store"),
                cloudKitDatabase: cloudKitContainer.map { .private($0) } ?? .none
            )
        }
        return try ModelContainer(for: schema, migrationPlan: ExamPrepMigrationPlan.self, configurations: [configuration])
    }
}
