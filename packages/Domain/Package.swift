// swift-tools-version: 6.0
// Domain 層。Foundation と DomainModels 以外に依存しない(DDD 5.3 R-01)。
// ターゲットは DDD-P1 3.1 の構成のうち、実装済みのステップの分だけを宣言する(空のターゲットは SwiftPM がエラーにするため)。
import PackageDescription

let package = Package(
    name: "Domain",
    platforms: [.iOS(.v18), .macOS(.v15)],
    products: [
        .library(name: "DomainInterfaces", targets: ["DomainInterfaces"]),
        .library(name: "StudyModels", targets: ["StudyModels"]),
        .library(name: "ExamEngine", targets: ["ExamEngine"]),
        .library(name: "FSRS", targets: ["FSRS"]),
        .library(name: "Readiness", targets: ["Readiness"]),
        .library(name: "QuestionSelector", targets: ["QuestionSelector"]),
        .library(name: "DomainTestSupport", targets: ["DomainTestSupport"]),
    ],
    dependencies: [
        .package(path: "../DomainModels"),
    ],
    targets: [
        .target(name: "DomainInterfaces", dependencies: ["DomainModels", "StudyModels", "ExamEngine", "FSRS", "QuestionSelector"]),
        .target(name: "StudyModels", dependencies: ["DomainModels"]),
        .target(name: "ExamEngine", dependencies: ["StudyModels", "DomainModels"]),
        // FSRS は学習内容に依存しないアルゴリズムなので、DomainModels にも依存させない
        .target(name: "FSRS"),
        .target(name: "Readiness", dependencies: ["StudyModels", "DomainModels"]),
        .target(name: "QuestionSelector", dependencies: ["StudyModels", "DomainModels"]),
        .target(name: "DomainTestSupport", dependencies: ["StudyModels", "DomainModels"]),
        .testTarget(name: "StudyModelsTests", dependencies: ["StudyModels", "DomainTestSupport"]),
        .testTarget(name: "ExamEngineTests", dependencies: ["ExamEngine", "DomainTestSupport"]),
        .testTarget(name: "FSRSTests", dependencies: ["FSRS"], resources: [.process("Vectors")]),
        .testTarget(name: "ReadinessTests", dependencies: ["Readiness", "DomainTestSupport"]),
        .testTarget(name: "QuestionSelectorTests", dependencies: ["QuestionSelector", "DomainTestSupport"]),
        .testTarget(name: "DomainTestSupportTests", dependencies: ["DomainTestSupport"]),
    ],
    swiftLanguageModes: [.v6]
)
