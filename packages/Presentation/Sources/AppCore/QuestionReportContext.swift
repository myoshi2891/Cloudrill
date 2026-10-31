import DomainModels

/// 誤り報告のシート(SCR-090)へ渡す、表示中のコンテンツを特定する値。
/// 解説画面(ExamFeature)と報告シート(SettingsFeature)が共有するため AppCore に置く。
public struct QuestionReportContext: Identifiable, Equatable, Sendable {
    public let examID: ExamID
    public let questionID: String
    public let questionRevision: Int
    public let packVersion: String
    public var id: String { "\(examID)/\(packVersion)/\(questionID)/\(questionRevision)" }
    public init(examID: ExamID, questionID: String, questionRevision: Int, packVersion: String) {
        self.examID = examID; self.questionID = questionID
        self.questionRevision = questionRevision; self.packVersion = packVersion
    }
}

/// 報告に添える端末側の情報(C-11)。Composition root が Bundle と Locale から作る。
public struct ReportMetadata: Equatable, Sendable {
    public let appVersion: String
    public let locale: String
    public init(appVersion: String, locale: String) { self.appVersion = appVersion; self.locale = locale }
}
