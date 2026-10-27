import Foundation
import SwiftData

public enum ModelContainerFactoryError: Error, Equatable, Sendable {
    case storeDirectoryRequired
    case invalidStoreDirectory
}

/// P3-S01 の assertion Red 用。ディスク指定でもメモリに作る仮実装。
public enum ModelContainerFactory {
    public static func make(
        inMemory: Bool,
        cloudKitContainer: String?,
        storeDirectory: URL? = nil
    ) throws -> ModelContainer {
        let schema = Schema(SchemaV1.models)
        let configuration = ModelConfiguration(
            "P3S01Red", schema: schema, isStoredInMemoryOnly: true,
            groupContainer: .none, cloudKitDatabase: .none
        )
        return try ModelContainer(for: schema, configurations: [configuration])
    }
}
