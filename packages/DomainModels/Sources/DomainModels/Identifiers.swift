import Foundation

/// 試験語彙(DDD 4.3 の②)の ID。値の妥当性は CI と ContentIntegrityChecker が確認するので、デコード時は空文字だけを拒否する。
public protocol StringIdentifier: RawRepresentable, Codable, Hashable, Sendable, Comparable,
    CustomStringConvertible, ExpressibleByStringLiteral where RawValue == String {
    init(rawValue: String)
}

extension StringIdentifier {
    public init(stringLiteral value: String) { self.init(rawValue: value) }
    public var description: String { rawValue }
    public static func < (lhs: Self, rhs: Self) -> Bool { lhs.rawValue < rhs.rawValue }

    public init(from decoder: any Decoder) throws {
        let container = try decoder.singleValueContainer()
        let value = try container.decode(String.self)
        guard !value.isEmpty else {
            throw DecodingError.dataCorruptedError(in: container, debugDescription: "ID が空です")
        }
        self.init(rawValue: value)
    }

    public func encode(to encoder: any Encoder) throws {
        var container = encoder.singleValueContainer()
        try container.encode(rawValue)
    }
}

/// 試験の ID(<ベンダー略称>-<試験略称> を推奨)。exams/<examID>/ のディレクトリ名と一致する
public struct ExamID: StringIdentifier {
    public let rawValue: String
    public init(rawValue: String) { self.rawValue = rawValue }
}

/// ベンダーの ID(例: google-cloud)
public struct VendorID: StringIdentifier {
    public let rawValue: String
    public init(rawValue: String) { self.rawValue = rawValue }
}

/// common.schema.json#/$defs/CaseStudyID。実在は exam.yaml の caseStudies で確認する
public struct CaseStudyID: StringIdentifier {
    public let rawValue: String
    public init(rawValue: String) { self.rawValue = rawValue }
}

/// common.schema.json#/$defs/WAFPillarID。実在は exam.yaml の taxonomies.wafPillars で確認する
public struct WAFPillarID: StringIdentifier {
    public let rawValue: String
    public init(rawValue: String) { self.rawValue = rawValue }
}

/// 試験の中でだけ一意な ID を、試験をまたいで扱うための組(DDD 4.7)。
public struct ExamScoped<ID: Hashable & Sendable>: Hashable, Sendable {
    public var examID: ExamID
    public var id: ID
    public init(examID: ExamID, id: ID) {
        self.examID = examID
        self.id = id
    }
}
