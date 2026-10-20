import Foundation

/// flashcard.schema.json#/$defs/Flashcard
public struct Flashcard: Codable, Hashable, Sendable, Identifiable {
    public var id: String
    public var domain: Int
    public var subObjective: String
    public var front: LocalizedText
    public var back: LocalizedText
    public var relatedQuestionIDs: [String]
}

/// flashcard.schema.json(flashcards/*.yaml 1ファイル分)
public struct FlashcardFile: Codable, Hashable, Sendable {
    public var cards: [Flashcard]
}
