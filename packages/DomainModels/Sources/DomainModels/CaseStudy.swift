import Foundation

/// case.schema.json(1ファイル1ケース)
public struct CaseStudy: Codable, Hashable, Sendable, Identifiable {
    public var id: CaseStudyID
    public var name: LocalizedText
    public var summary: LocalizedText
    public var businessRequirements: [LocalizedText]
    public var technicalRequirements: [LocalizedText]
    public var existingEnvironment: LocalizedText
    public var officialURL: URL
    public var requirementMappings: [RequirementMapping]
}

extension CaseStudy {
    /// `officialURL` は SwiftUI の Link に渡すので、デコードの時点で https に限る。
    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(CaseStudyID.self, forKey: .id)
        name = try container.decode(LocalizedText.self, forKey: .name)
        summary = try container.decode(LocalizedText.self, forKey: .summary)
        businessRequirements = try container.decode([LocalizedText].self, forKey: .businessRequirements)
        technicalRequirements = try container.decode([LocalizedText].self, forKey: .technicalRequirements)
        existingEnvironment = try container.decode(LocalizedText.self, forKey: .existingEnvironment)
        officialURL = try container.decodeHTTPSURL(forKey: .officialURL)
        requirementMappings = try container.decode([RequirementMapping].self, forKey: .requirementMappings)
    }
}

/// case.schema.json#/$defs/RequirementMapping
public struct RequirementMapping: Codable, Hashable, Sendable {
    public var requirement: LocalizedText
    public var recommendedServices: [String]
    public var rationale: LocalizedText
    public var rejectedOptions: [RejectedOption]
}

/// case.schema.json#/$defs/RejectedOption
public struct RejectedOption: Codable, Hashable, Sendable {
    public var service: String
    public var reason: LocalizedText
}
