import DomainInterfaces
import StudyModels
import ExamEngine
import SwiftUI

/// 具象リポジトリの生成はアプリの Composition root が担当する。
public struct AppDependencies: Sendable {
    public let pins: any PackPinning
    public let attempts: any ExamAttemptRepository
    public let answers: any AnswerHistoryRepository
    public let cards: any CardStateRepository
    public let bookmarks: any BookmarkRepository
    public let settings: any SettingsRepository
    public let dataManagement: any DataManagementRepository
    public let time: any TimeSource
    public let evaluators: AnswerEvaluatorRegistry
    public let seedProvider: @Sendable () -> UInt64

    public init(pins: any PackPinning, attempts: any ExamAttemptRepository, answers: any AnswerHistoryRepository,
                cards: any CardStateRepository, bookmarks: any BookmarkRepository,
                settings: any SettingsRepository, dataManagement: any DataManagementRepository,
                time: any TimeSource, evaluators: AnswerEvaluatorRegistry = .standard,
                seedProvider: @escaping @Sendable () -> UInt64) {
        self.pins = pins; self.attempts = attempts; self.answers = answers; self.cards = cards; self.bookmarks = bookmarks
        self.settings = settings; self.dataManagement = dataManagement; self.time = time
        self.evaluators = evaluators; self.seedProvider = seedProvider
    }
}

extension EnvironmentValues {
    // 未注入なら nil。Preview のために本番ストアを暗黙に生成しない。
    @Entry public var appDependencies: AppDependencies? = nil
}
