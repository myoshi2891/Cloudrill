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

    init(context: ModelContext) throws {
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
}
