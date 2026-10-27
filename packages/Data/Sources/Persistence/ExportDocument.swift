import Foundation

/// exportVersion 1: 日時は Unix epoch の秒（小数あり）、Data は Base64、関係は UUID。
/// JSON 自体を文字列から再構成せず、保存された Data の全バイトを保持する。
struct ExportDocument: Codable, Sendable {
    var exportVersion = 1
    var schema = "V1"
    var entities: [String: [[String: ExportValue]]]
}

enum ExportValue: Codable, Sendable {
    case string(String), integer(Int), number(Double), bool(Bool), array([ExportValue]), null
    init(from decoder: any Decoder) throws {
        let container = try decoder.singleValueContainer()
        if container.decodeNil() { self = .null }
        else if let value = try? container.decode(Bool.self) { self = .bool(value) }
        else if let value = try? container.decode(String.self) { self = .string(value) }
        else if let value = try? container.decode(Int.self) { self = .integer(value) }
        else if let value = try? container.decode(Double.self) { self = .number(value) }
        else { self = .array(try container.decode([ExportValue].self)) }
    }
    func encode(to encoder: any Encoder) throws {
        var container = encoder.singleValueContainer()
        switch self {
        case .string(let value): try container.encode(value)
        case .integer(let value): try container.encode(value)
        case .number(let value): try container.encode(value)
        case .bool(let value): try container.encode(value)
        case .array(let value): try container.encode(value)
        case .null: try container.encodeNil()
        }
    }
    static func text(_ value: String?) -> Self { value.map(Self.string) ?? .null }
    static func uuid(_ value: UUID?) -> Self { text(value?.uuidString) }
    static func date(_ value: Date?) -> Self { value.map { .number($0.timeIntervalSince1970) } ?? .null }
    static func data(_ value: Data) -> Self { .string(value.base64EncodedString()) }
    static func ids(_ values: [UUID]?) -> Self { values.map { .array($0.map(\.uuidString).sorted().map(Self.string)) } ?? .null }
}

extension PersistenceRows {
    private func exportRows<T>(_ rows: [T], id: KeyPath<T, UUID>, convert: (T) -> [String: ExportValue]) -> [[String: ExportValue]] {
        rows.sorted { $0[keyPath: id].uuidString < $1[keyPath: id].uuidString }.map(convert)
    }
    func exportDocument() -> ExportDocument {
        ExportDocument(entities: [
            "ExamAttempt": exportRows(examAttempts, id: \.id) { row in [
                "id": .uuid(row.id), "examID": .text(row.examID), "examSet": .integer(row.examSet), "packVersion": .text(row.packVersion),
                "startedAt": .date(row.startedAt), "statusRaw": .text(row.statusRaw), "submitReasonRaw": .text(row.submitReasonRaw),
                "submittedAt": .date(row.submittedAt), "correctCount": .integer(row.correctCount), "totalCount": .integer(row.totalCount),
                "sessionSnapshotJSON": .data(row.sessionSnapshotJSON), "answers": .ids(row.answers?.map(\.id)),
            ] },
            "AnswerRecord": exportRows(answerRecords, id: \.id) { row in [
                "id": .uuid(row.id), "examID": .text(row.examID), "questionID": .text(row.questionID), "questionRevision": .integer(row.questionRevision),
                "domain": .integer(row.domain), "subObjective": .text(row.subObjective), "caseStudy": .text(row.caseStudy),
                "selectionJSON": .data(row.selectionJSON), "isCorrect": .bool(row.isCorrect), "modeRaw": .text(row.modeRaw),
                "elapsedSeconds": .integer(row.elapsedSeconds), "answeredAt": .date(row.answeredAt), "attempt": .uuid(row.attempt?.id),
            ] },
            "CardState": exportRows(cardStates, id: \.id) { row in [
                "id": .uuid(row.id), "examID": .text(row.examID), "cardID": .text(row.cardID), "fsrsCardJSON": .data(row.fsrsCardJSON),
                "due": .date(row.due), "lastReview": .date(row.lastReview), "reviewLogs": .ids(row.reviewLogs?.map(\.id)),
            ] },
            "ReviewLog": exportRows(reviewLogs, id: \.id) { row in [
                "id": .uuid(row.id), "examID": .text(row.examID), "cardID": .text(row.cardID), "rating": .integer(row.rating),
                "elapsedDays": .number(row.elapsedDays), "reviewedAt": .date(row.reviewedAt), "cardState": .uuid(row.cardState?.id),
            ] },
            "PracticeServeLog": exportRows(practiceServeLogs, id: \.id) { row in [
                "id": .uuid(row.id), "examID": .text(row.examID), "questionID": .text(row.questionID), "servedAt": .date(row.servedAt),
            ] },
            "Flag": exportRows(flags, id: \.id) { row in [
                "id": .uuid(row.id), "examID": .text(row.examID), "questionID": .text(row.questionID), "createdAt": .date(row.createdAt),
            ] },
            "Bookmark": exportRows(bookmarks, id: \.id) { row in [
                "id": .uuid(row.id), "examID": .text(row.examID), "targetType": .text(row.targetType), "targetID": .text(row.targetID), "createdAt": .date(row.createdAt),
            ] },
            "ReadMark": exportRows(readMarks, id: \.id) { row in [
                "id": .uuid(row.id), "examID": .text(row.examID), "docSubObjective": .text(row.docSubObjective), "readAt": .date(row.readAt),
            ] },
            "UserSettings": exportRows(userSettings, id: \.id) { row in [
                "id": .uuid(row.id), "currentExamID": .text(row.currentExamID), "displayLanguage": .text(row.displayLanguage),
                "notificationsEnabled": .bool(row.notificationsEnabled), "shuffleChoices": .bool(row.shuffleChoices), "updatedAt": .date(row.updatedAt),
            ] },
            "ExamPreference": exportRows(examPreferences, id: \.id) { row in [
                "id": .uuid(row.id), "examID": .text(row.examID), "examDate": .date(row.examDate), "dailyNewCards": .integer(row.dailyNewCards),
                "dailyReviewLimit": .integer(row.dailyReviewLimit), "desiredRetention": .number(row.desiredRetention),
                "autoCardFromMistakes": .bool(row.autoCardFromMistakes), "updatedAt": .date(row.updatedAt),
            ] },
        ])
    }
}
