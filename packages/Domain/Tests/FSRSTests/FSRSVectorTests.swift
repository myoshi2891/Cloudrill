import Foundation
import Testing
@testable import FSRS

/// fsrs-vectors.json の形(content/scripts/fsrs_vectors.py が生成する)
struct VectorFile: Decodable {
    struct Generator: Decodable {
        var library: String
        var version: String
        var fsrsVersion: String
    }

    struct Parameters: Decodable {
        var w: [Double]
        var desiredRetention: Double
        /// 秒
        var learningSteps: [Int]
        /// 秒
        var relearningSteps: [Int]
        var maximumInterval: Int
        var enableFuzzing: Bool
    }

    struct Review: Decodable {
        var rating: Int
        var at: Date
    }

    struct Expected: Decodable {
        var phase: String
        var step: Int?
        var stability: Double
        var difficulty: Double
        var due: Date
        var retrievabilityAtDue: Double
    }

    struct Case: Decodable {
        var name: String
        var start: Date
        var reviews: [Review]
        var expected: [Expected]
    }

    var generator: Generator
    var parameters: Parameters
    var cases: [Case]

    static func load() throws -> VectorFile {
        let url = try #require(Bundle.module.url(forResource: "fsrs-vectors", withExtension: "json"))
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return try decoder.decode(VectorFile.self, from: Data(contentsOf: url))
    }

    func makeParameters() throws -> FSRSParameters {
        try FSRSParameters(
            w: parameters.w,
            desiredRetention: parameters.desiredRetention,
            learningSteps: parameters.learningSteps.map { .seconds($0) },
            relearningSteps: parameters.relearningSteps.map { .seconds($0) },
            maximumInterval: parameters.maximumInterval
        )
    }
}

/// 相対誤差で比べる(DDD-P1 P1-S08a の許容誤差)
func relativelyEqual(_ actual: Double, _ expected: Double, tolerance: Double = 1e-9) -> Bool {
    abs(actual - expected) <= tolerance * max(abs(expected), .leastNormalMagnitude)
}

@Suite("FSRS のテストベクタ")
struct FSRSVectorTests {
    @Test("ベクタは固定した版から生成され、必要な系列を含む")
    func vectorsAreWellFormed() throws {
        // Act
        let vectors = try VectorFile.load()
        // Assert
        #expect(vectors.generator.library == "py-fsrs")
        #expect(vectors.generator.version == "6.3.2")
        #expect(vectors.generator.fsrsVersion == "FSRS-6")
        #expect(vectors.parameters.w.count == 21)
        #expect(vectors.parameters.desiredRetention == 0.9)
        #expect(!vectors.parameters.enableFuzzing)
        let names = Set(vectors.cases.map(\.name))
        for required in ["new-again", "new-hard", "new-good", "new-easy", "good-streak", "lapse-and-recover", "early-review", "late-review", "same-day-review"] {
            #expect(names.contains(required), "\(required) がない")
        }
        for vectorCase in vectors.cases {
            #expect(vectorCase.reviews.count == vectorCase.expected.count, "\(vectorCase.name)")
        }
    }

    @Test("すべてのケースで、評価を順に当てた結果が期待値と一致する")
    func allVectors() throws {
        // Arrange
        let vectors = try VectorFile.load()
        let scheduler = FSRSScheduler(parameters: try vectors.makeParameters())
        // P1-S08d で FSRSScheduler を実装したら withKnownIssue を外す
        withKnownIssue("FSRSScheduler は仮の実装(P1-S08b〜d で実装する)") {
            for vectorCase in vectors.cases {
                var card = FSRSCard.new(at: vectorCase.start)
                for (index, (review, expected)) in zip(vectorCase.reviews, vectorCase.expected).enumerated() {
                    let label = "\(vectorCase.name)[\(index)]"
                    let rating = try #require(Rating(rawValue: review.rating), "\(label): 評価 \(review.rating)")
                    // Act
                    card = scheduler.review(card, rating: rating, at: review.at).card
                    // Assert
                    #expect(card.phase == CardPhase(rawValue: expected.phase), "\(label): phase")
                    #expect(card.step == expected.step, "\(label): step")
                    #expect(relativelyEqual(card.stability, expected.stability), "\(label): stability \(card.stability) ≠ \(expected.stability)")
                    #expect(relativelyEqual(card.difficulty, expected.difficulty), "\(label): difficulty \(card.difficulty) ≠ \(expected.difficulty)")
                    #expect(abs(card.due.timeIntervalSince(expected.due)) <= 1, "\(label): due \(card.due) ≠ \(expected.due)")
                    let retrievability = scheduler.retrievability(of: card, at: card.due)
                    #expect(relativelyEqual(retrievability, expected.retrievabilityAtDue), "\(label): retrievability \(retrievability) ≠ \(expected.retrievabilityAtDue)")
                }
            }
        }
    }
}
