import Foundation
import SwiftData
import Testing
@testable import Persistence

@MainActor
struct SchemaV1Tests {
    // DDD-P3 3.1 の永続化する列。リレーションは別のテストで確認する。
    private static let expectedAttributes: [String: Set<String>] = [
        "ExamAttempt": ["id", "examID", "examSet", "packVersion", "startedAt", "statusRaw", "submitReasonRaw", "submittedAt", "correctCount", "totalCount", "sessionSnapshotJSON"],
        "AnswerRecord": ["id", "examID", "questionID", "questionRevision", "domain", "subObjective", "caseStudy", "selectionJSON", "isCorrect", "modeRaw", "elapsedSeconds", "answeredAt"],
        "CardState": ["id", "examID", "cardID", "fsrsCardJSON", "due", "lastReview"],
        "ReviewLog": ["id", "examID", "cardID", "rating", "elapsedDays", "reviewedAt"],
        "PracticeServeLog": ["id", "examID", "questionID", "servedAt"],
        "Flag": ["id", "examID", "questionID", "createdAt"],
        "Bookmark": ["id", "examID", "targetType", "targetID", "createdAt"],
        "ReadMark": ["id", "examID", "docSubObjective", "readAt"],
        "UserSettings": ["id", "currentExamID", "displayLanguage", "notificationsEnabled", "shuffleChoices", "updatedAt"],
        "ExamPreference": ["id", "examID", "examDate", "dailyNewCards", "dailyReviewLimit", "desiredRetention", "autoCardFromMistakes", "updatedAt"],
    ]

    @Test func containerOpensInMemory() throws {
        let container = try ModelContainerFactory.make(inMemory: true, cloudKitContainer: nil)
        let configuration = try #require(container.configurations.first)
        #expect(container.configurations.count == 1)
        #expect(configuration.isStoredInMemoryOnly)
        #expect(configuration.cloudKitContainerIdentifier == nil)
        #expect(Set(container.schema.entities.map(\.name)) == Set(Self.expectedAttributes.keys))
    }

    @Test func schemaContainsAllColumns() throws {
        #expect(SchemaV1.versionIdentifier == Schema.Version(1, 0, 0))
        let schema = Schema(SchemaV1.models)
        #expect(schema.entities.count == 10)
        for (name, attributes) in Self.expectedAttributes {
            let entity = try #require(schema.entities.first { $0.name == name })
            #expect(Set(entity.attributes.map(\.name)) == attributes, "\(name) の永続化する列")
        }
    }

    @Test func allPropertiesHaveDefaults() throws {
        let models: [any PersistentModel] = [
            SchemaV1.ExamAttempt(), SchemaV1.AnswerRecord(), SchemaV1.CardState(),
            SchemaV1.ReviewLog(), SchemaV1.PracticeServeLog(), SchemaV1.Flag(),
            SchemaV1.Bookmark(), SchemaV1.ReadMark(), SchemaV1.UserSettings(), SchemaV1.ExamPreference(),
        ]
        #expect(models.count == SchemaV1.models.count)
        let schema = Schema(SchemaV1.models)
        // 引数なしで作れるだけでは不十分。CloudKit が参照する Schema にも既定値が必要。
        for entity in schema.entities {
            for attribute in entity.attributes {
                #expect(attribute.isOptional || attribute.defaultValue != nil,
                        "\(entity.name).\(attribute.name) に既定値か Optional が必要")
            }
        }
        let container = try ModelContainerFactory.make(inMemory: true, cloudKitContainer: nil)
        let context = ModelContext(container)
        for model in models { context.insert(model) }
        try context.save()
        #expect(!context.hasChanges)
    }

    @Test func noUniqueAttributes() {
        let schema = Schema(SchemaV1.models)
        #expect(schema.entities.count == 10)
        for entity in schema.entities {
            #expect(entity.uniquenessConstraints.isEmpty, "\(entity.name) の unique 制約")
            #expect(entity.properties.allSatisfy { !$0.isUnique })
        }
    }

    @Test func relationshipsAreOptional() throws {
        let schema = Schema(SchemaV1.models)
        let pairs = [
            ("ExamAttempt", "AnswerRecord"), ("AnswerRecord", "ExamAttempt"),
            ("CardState", "ReviewLog"), ("ReviewLog", "CardState"),
        ]
        for (source, destination) in pairs {
            let entity = try #require(schema.entities.first { $0.name == source })
            let relationship = try #require(entity.relationships.first { $0.destination == destination })
            #expect(relationship.isOptional, "\(source) → \(destination) は Optional")
            #expect(relationship.inverseName != nil, "\(source) → \(destination) の逆リレーション")
        }
        for entity in schema.entities {
            #expect(entity.relationships.allSatisfy(\.isOptional))
        }
    }

    @Test func storeIsInAppGroup() throws {
        // App Group の URL はアプリ側で解決し、テストでは一時ディレクトリを注入する。
        let directory = FileManager.default.temporaryDirectory.appending(path: "SchemaV1Tests-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let container = try ModelContainerFactory.make(
            inMemory: false, cloudKitContainer: nil, storeDirectory: directory
        )
        let configuration = try #require(container.configurations.first)
        #expect(!configuration.isStoredInMemoryOnly)
        #expect(configuration.cloudKitContainerIdentifier == nil)
        #expect(configuration.url.deletingLastPathComponent().standardizedFileURL == directory.standardizedFileURL)
        let context = ModelContext(container)
        let flag = SchemaV1.Flag()
        flag.examID = "test-alpha"
        flag.questionID = "Q-1.1-0001"
        context.insert(flag)
        try context.save()
        #expect(FileManager.default.fileExists(atPath: configuration.url.path))
    }
}
