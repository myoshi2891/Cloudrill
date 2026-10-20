import Foundation

/// decision.schema.json(1ファイル1ツリー)
public struct DecisionTree: Codable, Hashable, Sendable, Identifiable {
    public var id: String
    public var title: LocalizedText
    public var rootNodeID: String
    public var nodes: [DecisionNode]

    public func node(id: String) -> DecisionNode? {
        nodes.first { $0.id == id }
    }
}

/// decision.schema.json#/$defs/Node
public struct DecisionNode: Codable, Hashable, Sendable, Identifiable {
    public var id: String
    public var question: LocalizedText
    public var options: [DecisionOption]
}

/// decision.schema.json#/$defs/Result
public struct DecisionResult: Codable, Hashable, Sendable {
    public var service: String
    public var rationale: LocalizedText
}

/// 選択肢を選んだ後の遷移先。JSON では `next` と `result` のどちらか一方だけを持つ。
public enum DecisionOutcome: Hashable, Sendable {
    case next(nodeID: String)
    case result(DecisionResult)
}

/// decision.schema.json#/$defs/Option
public struct DecisionOption: Hashable, Sendable {
    public var label: LocalizedText
    public var outcome: DecisionOutcome

    public init(label: LocalizedText, outcome: DecisionOutcome) {
        self.label = label
        self.outcome = outcome
    }
}

extension DecisionOption: Codable {
    private enum CodingKeys: String, CodingKey {
        case label, next, result
    }

    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        label = try container.decode(LocalizedText.self, forKey: .label)
        let next = try container.decodeIfPresent(String.self, forKey: .next)
        let result = try container.decodeIfPresent(DecisionResult.self, forKey: .result)
        switch (next, result) {
        case let (.some(nodeID), .none):
            outcome = .next(nodeID: nodeID)
        case let (.none, .some(result)):
            outcome = .result(result)
        default:
            throw DecodingError.dataCorrupted(.init(
                codingPath: container.codingPath,
                debugDescription: "next と result のどちらか一方だけを指定してください"
            ))
        }
    }

    public func encode(to encoder: any Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(label, forKey: .label)
        switch outcome {
        case let .next(nodeID):
            try container.encode(nodeID, forKey: .next)
        case let .result(result):
            try container.encode(result, forKey: .result)
        }
    }
}
