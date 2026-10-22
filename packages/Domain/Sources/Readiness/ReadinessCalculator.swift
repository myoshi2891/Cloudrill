import Foundation
import DomainModels
import StudyModels

public struct ReadinessInput: Sendable {
    public var definition: ExamDefinition
    public var answers: [AnswerFact]
    /// ドメイン番号 → 復習済みカードの現在の記憶保持率(呼び出し側が FSRS で計算する。Readiness は FSRS に依存しない)
    public var cardRetentions: [Int: [Double]]
    public var now: Date

    public init(definition: ExamDefinition, answers: [AnswerFact], cardRetentions: [Int: [Double]], now: Date) {
        self.definition = definition
        self.answers = answers
        self.cardRetentions = cardRetentions
        self.now = now
    }
}

/// ドメインごとの理解度(BDD 6.6)
public struct DomainReadiness: Hashable, Sendable {
    /// 直近の解答を重く見た正答率 `acc_d`。解答が 0 件なら nil
    public var accuracy: Double?
    /// カードの記憶保持率の平均 `ret_d`。復習済みのカードが 0 件なら nil
    public var retention: Double?
    /// 網羅度 `cov_d`(0〜1)
    public var coverage: Double
    /// 理解度 `score_d`(0〜1)
    public var score: Double

    public init(accuracy: Double?, retention: Double?, coverage: Double, score: Double) {
        self.accuracy = accuracy
        self.retention = retention
        self.coverage = coverage
        self.score = score
    }
}

public enum ReadinessResult: Hashable, Sendable {
    /// 解答したユニークな問題が足りない(「データ収集中」と表示する)
    case collecting(answeredUniqueQuestions: Int, required: Int)
    /// 準備度(0〜100)とドメインごとの内訳。内訳は試験定義のすべてのドメインを持つ
    case ready(score: Double, domains: [Int: DomainReadiness])
}

/// 合格準備度の計算(BDD 6.6)。`readiness = Σ_d (weight_d × score_d × cov_d) × 100`
public struct ReadinessCalculator: Sendable {
    /// 準備度の計算に含める解答のモード(drill はキーワードドリルで、問題ではないので含めない)
    static let countedModes: Set<StudyMode> = [.exam, .practice]
    private static let secondsPerDay: Double = 86_400

    public let parameters: ReadinessParameters

    public init(parameters: ReadinessParameters) { self.parameters = parameters }

    public func calculate(_ input: ReadinessInput) -> ReadinessResult {
        let answers = input.answers.filter { $0.examID == input.definition.id && Self.countedModes.contains($0.mode) }
        let uniqueQuestions = Set(answers.map(\.questionID)).count
        guard uniqueQuestions >= parameters.minimumUniqueQuestions else {
            return .collecting(answeredUniqueQuestions: uniqueQuestions, required: parameters.minimumUniqueQuestions)
        }

        let answersByDomain = Dictionary(grouping: answers, by: \.domain)
        let rows = input.definition.domains.map { domain in
            (domain, domainReadiness(
                answers: answersByDomain[domain.id] ?? [],
                retentions: input.cardRetentions[domain.id] ?? [],
                now: input.now
            ))
        }
        let score = rows.reduce(0.0) { sum, row in sum + row.0.weight * row.1.score * row.1.coverage } * 100
        let domains = Dictionary(rows.map { ($0.0.id, $0.1) }, uniquingKeysWith: { first, _ in first })
        return .ready(score: score, domains: domains)
    }

    /// 1ドメインの理解度。解答が 0 件なら score 0、カードが 0 件なら正答率だけで決める(BDD 6.6)
    func domainReadiness(answers: [AnswerFact], retentions: [Double], now: Date) -> DomainReadiness {
        let retention = retentions.isEmpty ? nil : retentions.reduce(0, +) / Double(retentions.count)
        guard !answers.isEmpty else {
            return DomainReadiness(accuracy: nil, retention: retention, coverage: 0, score: 0)
        }

        let weights = answers.map { recencyWeight(answeredAt: $0.answeredAt, now: now) }
        let correctWeight = zip(answers, weights).reduce(0.0) { sum, pair in sum + (pair.0.isCorrect ? pair.1 : 0) }
        let accuracy = correctWeight / weights.reduce(0, +)
        let coverage = min(1, Double(Set(answers.map(\.questionID)).count) / Double(parameters.coverageTarget))
        let score = retention.map { parameters.accuracyWeight * accuracy + parameters.retentionWeight * $0 } ?? accuracy
        return DomainReadiness(accuracy: accuracy, retention: retention, coverage: coverage, score: score)
    }

    /// 解答の重み `0.5^(t / halfLifeDays)`。t は解答からの経過日数で、負(端末間の時計のずれ)なら 0 とする
    func recencyWeight(answeredAt: Date, now: Date) -> Double {
        let elapsedDays = max(0, now.timeIntervalSince(answeredAt) / Self.secondsPerDay)
        return pow(0.5, elapsedDays / parameters.halfLifeDays)
    }
}
