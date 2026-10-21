import Foundation

/// 出題順と選択肢の並び。乱数の状態ではなく、決まった結果を保存する(DDD 6.3)。
public struct QuestionOrder: Codable, Hashable, Sendable {
    public static let currentVersion = 1
    public var version: Int
    public var items: [Item]

    public struct Item: Codable, Hashable, Sendable {
        public var questionID: String
        /// 表示する順の選択肢 ID
        public var choiceIDs: [String]

        public init(questionID: String, choiceIDs: [String]) {
            self.questionID = questionID
            self.choiceIDs = choiceIDs
        }
    }

    public init(items: [Item]) {
        version = Self.currentVersion
        self.items = items
    }

    private enum CodingKeys: String, CodingKey {
        case version
        case items
    }

    /// 版を確かめてから読む。未来の版は形が変わっている可能性があるので、全体をデコードする前に判定する。
    public static func decode(from data: Data) throws(QuestionOrderError) -> QuestionOrder {
        let decoder = JSONDecoder()
        let header: VersionHeader
        do {
            header = try decoder.decode(VersionHeader.self, from: data)
        } catch {
            throw .invalidData(underlying: error)
        }
        guard header.version == currentVersion else {
            throw .unsupportedVersion(header.version)
        }
        do {
            return try decoder.decode(QuestionOrder.self, from: data)
        } catch {
            throw .invalidData(underlying: error)
        }
    }

    private struct VersionHeader: Decodable {
        var version: Int

        init(from decoder: any Decoder) throws {
            let container = try decoder.container(keyedBy: CodingKeys.self)
            version = try container.decode(Int.self, forKey: .version)
        }
    }
}

public enum QuestionOrderError: Error {
    /// このアプリが読めない版(currentVersion 以外)
    case unsupportedVersion(Int)
    /// JSON として読めない、または項目が欠けている
    case invalidData(underlying: any Error)
    /// 出題順にある問題が、コンテンツにない
    case missingQuestion(String)
    /// 保存した選択肢の ID が、問題の選択肢と一致しない(問題が改訂された場合など)
    case choicesMismatch(questionID: String)
}
