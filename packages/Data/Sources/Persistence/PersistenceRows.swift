import Foundation
import SwiftData

/// 同期後の統合とデータ管理だけで使う、actor 内の全件読み取り。
/// ModelContext とこれらのモデルを actor の外には渡さない。
struct PersistenceRows {
    let examAttempts: [SchemaV1.ExamAttempt]
    let answerRecords: [SchemaV1.AnswerRecord]
    let cardStates: [SchemaV1.CardState]
    let reviewLogs: [SchemaV1.ReviewLog]
    let practiceServeLogs: [SchemaV1.PracticeServeLog]
    let flags: [SchemaV1.Flag]
    let bookmarks: [SchemaV1.Bookmark]
    let readMarks: [SchemaV1.ReadMark]
    let userSettings: [SchemaV1.UserSettings]
    let examPreferences: [SchemaV1.ExamPreference]

    init(context: ModelContext, examID: String? = nil) throws {
        if let exam = examID {
            examAttempts = try context.fetch(FetchDescriptor<SchemaV1.ExamAttempt>(predicate: #Predicate { $0.examID == exam }))
            answerRecords = try context.fetch(FetchDescriptor<SchemaV1.AnswerRecord>(predicate: #Predicate { $0.examID == exam }))
            cardStates = try context.fetch(FetchDescriptor<SchemaV1.CardState>(predicate: #Predicate { $0.examID == exam }))
            reviewLogs = try context.fetch(FetchDescriptor<SchemaV1.ReviewLog>(predicate: #Predicate { $0.examID == exam }))
            practiceServeLogs = try context.fetch(FetchDescriptor<SchemaV1.PracticeServeLog>(predicate: #Predicate { $0.examID == exam }))
            flags = try context.fetch(FetchDescriptor<SchemaV1.Flag>(predicate: #Predicate { $0.examID == exam }))
            bookmarks = try context.fetch(FetchDescriptor<SchemaV1.Bookmark>(predicate: #Predicate { $0.examID == exam }))
            readMarks = try context.fetch(FetchDescriptor<SchemaV1.ReadMark>(predicate: #Predicate { $0.examID == exam }))
            examPreferences = try context.fetch(FetchDescriptor<SchemaV1.ExamPreference>(predicate: #Predicate { $0.examID == exam }))
            // 全体設定は試験指定の出力・削除の対象外。
            userSettings = []
            return
        }
        examAttempts = try context.fetch(FetchDescriptor<SchemaV1.ExamAttempt>())
        answerRecords = try context.fetch(FetchDescriptor<SchemaV1.AnswerRecord>())
        cardStates = try context.fetch(FetchDescriptor<SchemaV1.CardState>())
        reviewLogs = try context.fetch(FetchDescriptor<SchemaV1.ReviewLog>())
        practiceServeLogs = try context.fetch(FetchDescriptor<SchemaV1.PracticeServeLog>())
        flags = try context.fetch(FetchDescriptor<SchemaV1.Flag>())
        bookmarks = try context.fetch(FetchDescriptor<SchemaV1.Bookmark>())
        readMarks = try context.fetch(FetchDescriptor<SchemaV1.ReadMark>())
        userSettings = try context.fetch(FetchDescriptor<SchemaV1.UserSettings>())
        examPreferences = try context.fetch(FetchDescriptor<SchemaV1.ExamPreference>())
    }

    func deleteAll(in context: ModelContext) {
        // 子を先に削除し、親の nullify によって不要な関係が残ることを避ける。
        for row in answerRecords { context.delete(row) }
        for row in reviewLogs { context.delete(row) }
        for row in examAttempts { context.delete(row) }
        for row in cardStates { context.delete(row) }
        for row in practiceServeLogs { context.delete(row) }
        for row in flags { context.delete(row) }
        for row in bookmarks { context.delete(row) }
        for row in readMarks { context.delete(row) }
        for row in userSettings { context.delete(row) }
        for row in examPreferences { context.delete(row) }
    }
}
