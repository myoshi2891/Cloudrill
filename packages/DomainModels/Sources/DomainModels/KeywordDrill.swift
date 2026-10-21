import Foundation

/// drill.schema.json#/$defs/KeywordDrill
public struct KeywordDrill: Codable, Hashable, Sendable, Identifiable {
    public var id: String
    public var phrase: LocalizedText
    public var correct: String
    public var distractor: String
    public var explanation: LocalizedText
}

/// drill.schema.json(drills/keywords.yaml 1ファイル分)
public struct KeywordDrillFile: Codable, Hashable, Sendable {
    public var drills: [KeywordDrill]
}
