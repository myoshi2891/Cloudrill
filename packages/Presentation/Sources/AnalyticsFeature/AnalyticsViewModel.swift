import Foundation
import Observation
import AppCore
import DomainModels
import DomainInterfaces
import StudyModels

/// 正答率の1行(ドメインまたはサブ項目)
public struct AnalyticsRow: Hashable, Sendable, Identifiable {
    public var id: String
    public var name: LocalizedText
    public var tally: ScoreTally
    /// 四捨五入した整数の %。解答が 0 件なら「—」(0% と区別する)
    public var accuracyText: String {
        guard let ratio = tally.ratio else { return "—" }
        return "\(Int((ratio * 100).rounded()))%"
    }
}

public struct AnalyticsSection: Hashable, Sendable, Identifiable {
    public var id: Int
    /// 試験定義でのドメインの位置(配色用)
    public var domainIndex: Int
    public var domain: AnalyticsRow
    /// 解答のあるサブ項目だけを、定義の順で出す
    public var subObjectives: [AnalyticsRow]
}

public struct AnalyticsState: Equatable, Sendable {
    public var sections: [AnalyticsSection] = []
    public var isLoading = false
    public var isLoaded = false
    public var loadFailed = false
    /// どのドメインにも解答がない
    public var isEmpty: Bool { sections.allSatisfy { $0.domain.tally.total == 0 } }
}

/// 分析トップ(SCR-050)。選択中の試験の解答だけを、ドメイン別・サブ項目別に集計する(FR-ANLY-01)
@MainActor @Observable public final class AnalyticsViewModel {
    public private(set) var state = AnalyticsState()
    public let definition: ExamDefinition
    private let answers: any AnswerHistoryRepository
    private var rerunRequested = false

    public init(definition: ExamDefinition, answers: any AnswerHistoryRepository) {
        self.definition = definition; self.answers = answers
    }

    /// 読み込み中の呼び出しは捨てずに、完了後にもう一度読み直す(HomeViewModel と同じ)。
    /// 失敗したときは前回の集計を保つ。
    public func refresh() async {
        guard !state.isLoading else { rerunRequested = true; return }
        state.isLoading = true
        defer { state.isLoading = false }
        repeat {
            rerunRequested = false
            do {
                let outcomes = try await answers.outcomes(examID: definition.id)
                state.sections = Self.sections(definition: definition,
                                               summary: AccuracySummary(definition: definition, outcomes: outcomes))
                state.loadFailed = false
                state.isLoaded = true
            } catch { state.loadFailed = true }
        } while rerunRequested
    }

    static func sections(definition: ExamDefinition, summary: AccuracySummary) -> [AnalyticsSection] {
        let empty = ScoreTally(correct: 0, total: 0)
        return definition.domains.enumerated().map { index, domain in
            AnalyticsSection(
                id: domain.id, domainIndex: index,
                domain: AnalyticsRow(id: "\(domain.id)", name: domain.name, tally: summary.byDomain[domain.id] ?? empty),
                subObjectives: domain.subObjectives.compactMap { sub in
                    guard let tally = summary.bySubObjective[sub.id], tally.total > 0 else { return nil }
                    return AnalyticsRow(id: sub.id, name: sub.name, tally: tally)
                })
        }
    }
}
