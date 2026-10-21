import Foundation

/// 選択の形。出題形式(QuestionKind)を追加するときは case を追加する(DDD 4.10 C)。
/// Codable の形: `{"kind":"choices","choiceIDs":["a","c"]}`(choiceIDs は昇順に並べて出力する)
public enum AnswerSelection: Hashable, Sendable {
    case choices(Set<String>)
}

extension AnswerSelection: Codable {
    private enum CodingKeys: String, CodingKey {
        case kind
        case choiceIDs
    }

    /// 未知の値はデコードエラーにする(古いアプリで新しい形式を読まない)
    private enum Kind: String, Codable {
        case choices
    }

    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        switch try container.decode(Kind.self, forKey: .kind) {
        case .choices:
            self = .choices(try container.decode(Set<String>.self, forKey: .choiceIDs))
        }
    }

    public func encode(to encoder: any Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        switch self {
        case let .choices(ids):
            try container.encode(Kind.choices, forKey: .kind)
            // Set の順序は実行ごとに変わるので、保存する値を決定論的にするため並べる
            try container.encode(ids.sorted(), forKey: .choiceIDs)
        }
    }
}
