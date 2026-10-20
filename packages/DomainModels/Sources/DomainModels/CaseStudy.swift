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
