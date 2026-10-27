import SwiftData

public enum ExamPrepMigrationPlan: SchemaMigrationPlan {
    public static var schemas: [any VersionedSchema.Type] { [] }
    public static var stages: [MigrationStage] { [] }
}
