import Foundation
import SwiftData
import Testing
@testable import Persistence

@MainActor struct MigrationPlanTests {
    @Test func planListsV1WithNoMigrationStages() {
        #expect(ExamPrepMigrationPlan.schemas.map { ObjectIdentifier($0) } == [ObjectIdentifier(SchemaV1.self)])
        #expect(ExamPrepMigrationPlan.stages.isEmpty)
    }

    @Test func containerUsesPlan() throws {
        let container = try ModelContainerFactory.make(inMemory: true, cloudKitContainer: nil)
        // SwiftData が公開する実際の設定を確認する。Spy に置き換えず本物のコンテナを開く。
        let plan = try #require(container.migrationPlan)
        #expect(ObjectIdentifier(plan) == ObjectIdentifier(ExamPrepMigrationPlan.self))
        #expect(container.schema.version == SchemaV1.versionIdentifier)
    }

    @Test func reopensExistingV1StoreWithoutLosingRecords() throws {
        let root = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let id = UUID()
        // S01〜S08 の、移行計画を指定しなかったファクトリーと同じ条件で作る。
        do {
            let schema = Schema(SchemaV1.models)
            let configuration = ModelConfiguration("StudyHistory", schema: schema, url: root.appending(path: "StudyHistory.store"), cloudKitDatabase: .none)
            let container = try ModelContainer(for: schema, configurations: [configuration])
            let context = ModelContext(container)
            let flag = SchemaV1.Flag(); flag.id = id; flag.examID = "test-alpha"; flag.questionID = "Q1"
            context.insert(flag); try context.save()
        }
        let reopened = try ModelContainerFactory.make(inMemory: false, cloudKitContainer: nil, storeDirectory: root)
        #expect(reopened.migrationPlan != nil)
        let rows = try ModelContext(reopened).fetch(FetchDescriptor<SchemaV1.Flag>())
        #expect(rows.count == 1 && rows.first?.id == id)
        #expect(rows.first?.examID == "test-alpha" && rows.first?.questionID == "Q1")
    }
}
